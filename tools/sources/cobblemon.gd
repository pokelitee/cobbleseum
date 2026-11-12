extends RefCounted
## Build step for the Cobblemon source (concepts_brief.md §7, §8).
## Matches Showdown species to Cobblemon models (CobblemonRoster), converts each one into
## models/<id>.scn, and writes:
## - roster.json: one entry per species with its model, scale, height, hitbox radius, animations,
##   QA flags and licence. Headless simulation reads only this file.
## - report.json: the QA report, a summary plus each species' flags and conversion problems.
##
## Conversion is cached per species. Each model has a sidecar models/<id>.json with a key
## over its input files and the converter scripts, plus its measurements and report. A model
## whose key still matches is reused from an interrupted build (the staging folder) or the
## previous build, so only changed species are converted again.

const INCREMENTAL := true
const SHOWDOWN_POKEDEX := BattleData.SHOWDOWN_DIR + "/pokedex.json"
## Extra files whose changes invalidate the build stamp.
const DEPENDENCIES: Array[String] = [
	"res://tools/convert/bedrock_geometry.gd",
	"res://tools/convert/bedrock_animation.gd",
	"res://tools/convert/cobblemon_model.gd",
	"res://tools/convert/cobblemon_species.gd",
	"res://tools/convert/cobblemon_roster.gd",
	"res://tools/convert/molang.gd",
	SHOWDOWN_POKEDEX,
]
## The scripts that shape a converted model; changing one invalidates every cached model.
const CONVERTER: Array[String] = [
	"res://tools/convert/bedrock_geometry.gd",
	"res://tools/convert/bedrock_animation.gd",
	"res://tools/convert/cobblemon_model.gd",
	"res://tools/convert/cobblemon_species.gd",
	"res://tools/convert/molang.gd",
]
const LICENCE := "CC BY-NC 3.0"
const PROGRESS_EVERY := 100


func build(source_dir: String, out_dir: String, previous_dir := "") -> String:
	var pokedex: Variant = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path(SHOWDOWN_POKEDEX)))
	if not pokedex is Dictionary:
		return "%s is missing; build the showdown source first" % SHOWDOWN_POKEDEX
	var entries := CobblemonRoster.match_species(pokedex, CobblemonRoster.load_cobblemon(source_dir),
		CobblemonRoster.load_folders(source_dir))
	if entries.is_empty():
		return "no Showdown species matched a Cobblemon model"
	var models_dir := out_dir.path_join("models")
	DirAccess.make_dir_recursive_absolute(models_dir)
	var converter_key := "|".join(CONVERTER.map(func(p: String) -> String: return FileAccess.get_sha256(p)))

	var roster := {}
	var qa := {}
	var converted := 0
	var started := Time.get_ticks_msec()
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var files := CobblemonSpecies.files(source_dir, entry.folder, entry.aspects)
		if files.has("error"):
			qa[entry.id] = {"error": files.error}
			continue
		var key := _input_key(source_dir, entry.folder, files, converter_key)
		var sidecar := _cached(entry.id, key, models_dir, previous_dir.path_join("models") if not previous_dir.is_empty() else "")
		if sidecar.is_empty():
			var result := CobblemonModel.convert(source_dir, entry.folder, entry.aspects)
			if result.has("error"):
				qa[entry.id] = {"error": result.error}
				continue
			var err := ResourceSaver.save(result.scene, models_dir.path_join(entry.id + ".scn"))
			if err != OK:
				return "cannot save model %s (%s)" % [entry.id, error_string(err)]
			sidecar = {"key": key, "report": _json_report(result.report)}
			_write_json(models_dir.path_join(entry.id + ".json"), sidecar)
			converted += 1
		var listed := _roster_entry(entry, sidecar.report, source_dir)
		roster[entry.id] = listed.entry
		qa[entry.id] = listed.qa
		if (i + 1) % PROGRESS_EVERY == 0:
			print("  %d/%d species (%d converted, %d s)" % [i + 1, entries.size(), converted, (Time.get_ticks_msec() - started) / 1000])

	_prune(models_dir, roster)
	_write_json(out_dir.path_join("roster.json"), {"species": roster})
	_write_json(out_dir.path_join("report.json"), {"summary": summary(roster, qa), "species": qa})
	print("  roster: %d species (%d converted, %d reused, %d failed); see report.json" % [
		roster.size(), converted, roster.size() - converted, entries.size() - roster.size()])
	return ""


## The roster entry for a converted species, plus its QA record.
static func _roster_entry(entry: Dictionary, report: Dictionary, source_dir: String) -> Dictionary:
	var bounds := Vector3(report.bounds[0], report.bounds[1], report.bounds[2])
	var sized := CobblemonRoster.size(entry.hitbox, bounds, entry.base_scale)
	var flags: Array[String] = []
	for role: String in report.get("missing_roles", []):
		flags.append("no_" + role)
	if report.has("missing_texture"):
		flags.append("missing_texture")
	if not report.get("poser", false):
		flags.append("no_poser")
	if entry.hitbox.is_empty():
		flags.append("no_hitbox")
	var posed: Array = report.get("posed_bounds", report.bounds)
	var model_height := float(posed[1]) * float(entry.base_scale)
	var hitbox_height := float(entry.hitbox.get("height", bounds.y)) * float(entry.base_scale)
	if model_height > 0.0 and maxf(model_height, hitbox_height) / minf(model_height, hitbox_height) > CobblemonRoster.POSE_MISMATCH:
		flags.append("pose_mismatch")
	var licensed := FileAccess.file_exists(source_dir.path_join(CobblemonSpecies.BEDROCK).path_join("models").path_join(entry.folder).path_join("license"))
	if not licensed:
		flags.append("no_licence_file")
	for problem in ["unknown_bones", "molang_errors", "unknown_names"]:
		if report.has(problem):
			flags.append(problem)
	var roster_entry := {
		"name": entry.name, "num": entry.num, "folder": entry.folder, "aspects": entry.aspects,
		"model": entry.id + ".scn", "scale": sized.scale, "height": sized.height, "radius": sized.radius,
		"animations": (report.get("animations", {}) as Dictionary).keys(), "poser": report.get("poser", false),
		"flags": flags, "licence": LICENCE,
	}
	var qa := {"flags": flags, "model_height": model_height, "hitbox_height": hitbox_height}
	for problem in ["unknown_bones", "molang_errors", "unknown_names", "missing_texture"]:
		if report.has(problem):
			qa[problem] = report[problem]
	return {"entry": roster_entry, "qa": qa}


static func summary(roster: Dictionary, qa: Dictionary) -> Dictionary:
	var flags := {}
	for entry: Dictionary in roster.values():
		for flag: String in entry.flags:
			flags[flag] = flags.get(flag, 0) + 1
	var failed := qa.keys().filter(func(id: String) -> bool: return qa[id].has("error"))
	return {"species": roster.size(), "failed": failed, "species_with_flag": flags}


## Hash over everything the converted scene depends on: the model, texture and poser
## files, the species' animation files and the converter scripts.
static func _input_key(source_dir: String, folder: String, files: Dictionary, converter_key: String) -> String:
	var parts: PackedStringArray = [converter_key, files.geo.get_file(), FileAccess.get_sha256(files.geo)]
	parts.append(FileAccess.get_sha256(files.texture) if FileAccess.file_exists(files.texture) else "no-texture")
	for layer: Dictionary in files.layers:
		parts.append("layer:%s:%s" % [layer.emissive, FileAccess.get_sha256(layer.texture) if FileAccess.file_exists(layer.texture) else "missing"])
	var bedrock := source_dir.path_join(CobblemonSpecies.BEDROCK)
	var poser: String = bedrock.path_join("posers").path_join(folder).path_join(files.poser + ".json")
	parts.append(FileAccess.get_sha256(poser) if not files.poser.is_empty() and FileAccess.file_exists(poser) else "no-poser")
	var animations := bedrock.path_join("animations").path_join(folder)
	if DirAccess.dir_exists_absolute(animations):
		for file in DirAccess.get_files_at(animations):
			parts.append(file + ":" + FileAccess.get_sha256(animations.path_join(file)))
	return "|".join(parts).sha256_text()


## The sidecar of a model whose key matches, moving it from the previous build into
## `models_dir` if needed; {} when the species must be converted.
static func _cached(id: String, key: String, models_dir: String, previous_models: String) -> Dictionary:
	for dir in [models_dir, previous_models]:
		if dir.is_empty():
			continue
		var sidecar: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(id + ".json"))) \
			if FileAccess.file_exists(dir.path_join(id + ".json")) else null
		if not (sidecar is Dictionary and sidecar.get("key") == key and FileAccess.file_exists(dir.path_join(id + ".scn"))):
			continue
		if dir != models_dir:
			for ext in [".scn", ".json"]:
				if DirAccess.rename_absolute(dir.path_join(id + ext), models_dir.path_join(id + ext)) != OK:
					return {}
		return sidecar
	return {}


## Removes models of species no longer in the roster, e.g. left from an older build.
static func _prune(models_dir: String, roster: Dictionary) -> void:
	for file in DirAccess.get_files_at(models_dir):
		if not roster.has(file.get_basename()):
			DirAccess.remove_absolute(models_dir.path_join(file))


## Converter reports hold {name: true} sets; JSON keeps their sorted names.
static func _json_report(report: Dictionary) -> Dictionary:
	var out := {}
	for key: String in report:
		var value: Variant = report[key]
		if value is Dictionary and key != "animations":
			var names: Array = value.keys()
			names.sort()
			out[key] = names
		else:
			out[key] = value
	return out


static func _write_json(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  ", false))
	file.close()
