extends RefCounted
## Build step for the Cobblemon source (concepts_brief.md §7, §8).
## Matches Showdown species to Cobblemon models (CobblemonRoster), converts each one into
## models/<id>.scn and each of its cosmetic forms into models/<id>@<form>.scn, gives each of
## those looks its shiny (models/<look>~shiny.res, a skin, or .scn), and writes:
## - roster.json: one entry per species with its model, scale, height, hitbox radius, whether it flies, animations,
##   QA flags, licence, shiny and cosmetic forms. Headless simulation reads only this file.
## - report.json: the QA report, a summary plus each species' flags and conversion problems.
## - move_fx/: the move particle effects, their textures and the action effects, copied as they
##   are; CobblemonMoveFX runs them at presentation time (concepts_brief.md §12.5). The
##   Minecraft textures among them are replaced by our own (MoveFxSprites).
##
## Conversion is cached per look. Each model or skin has a sidecar models/<file>.json with a
## key over its input files and the converter scripts, plus a model's measurements and report.
## One whose key still matches is reused from an interrupted build (the staging folder) or the
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
	"res://tools/sprites/pixel_canvas.gd",
	"res://tools/sprites/move_fx_sprites.gd",
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
## Appended to a look's file name for its shiny: a skin (.res) or, when the shiny variation
## swaps the model or poser, a scene of its own (.scn).
const SHINY_SUFFIX := "~shiny"
## Folders copied to move_fx/ unchanged, relative to the source.
const MOVE_FX_DIRS: Array[String] = [
	"assets/cobblemon/bedrock/particles",
	"assets/cobblemon/textures/particle",
	"data/cobblemon/action_effects",
]


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
	var written := {}
	var previous_models := previous_dir.path_join("models") if not previous_dir.is_empty() else ""
	var started := Time.get_ticks_msec()
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var base := _look(entry.id, source_dir, entry.folder, entry.aspects, converter_key, models_dir, previous_models)
		if base.has("fatal"):
			return base.fatal
		if base.has("error"):
			qa[entry.id] = {"error": base.error}
			continue
		converted += base.converted
		written.merge(base.written)
		var listed := _roster_entry(entry, base.sidecar.report, source_dir)
		_add_shiny(listed, base, listed.entry)
		var forms := {}
		for form: Dictionary in entry.forms:
			var form_files := CobblemonSpecies.files(source_dir, entry.folder, form.aspects)
			if not form_files.has("error") and same_look(form_files, base.files):
				continue
			var look := _look("%s@%s" % [entry.id, form.id], source_dir, entry.folder, form.aspects, converter_key, models_dir, previous_models)
			if look.has("fatal"):
				return look.fatal
			if look.has("error"):
				listed.qa.get_or_add("form_errors", {})[form.id] = look.error
				continue
			converted += look.converted
			written.merge(look.written)
			forms[form.id] = {"name": form.name, "model": look.model}
			if form.has("chance"):
				forms[form.id].chance = form.chance
			_add_shiny(listed, look, forms[form.id])
		if not forms.is_empty():
			listed.entry.forms = forms
			listed.qa.forms = forms.keys()
		roster[entry.id] = listed.entry
		qa[entry.id] = listed.qa
		if (i + 1) % PROGRESS_EVERY == 0:
			print("  %d/%d species (%d models and skins converted, %d s)" % [i + 1, entries.size(), converted, (Time.get_ticks_msec() - started) / 1000])

	_prune(models_dir, written)
	var copied := 0
	for dir in MOVE_FX_DIRS:
		var count := _copy_tree(source_dir.path_join(dir), out_dir.path_join("move_fx").path_join(dir))
		if count < 0:
			return "cannot copy %s into the build" % dir
		copied += count
	print("  move effects: %d files" % copied)
	var sprites := MoveFxSprites.new().render_all(out_dir.path_join("move_fx").path_join(MOVE_FX_DIRS[1]))
	if not sprites.is_empty():
		return sprites
	print("  our own particle textures: %d drawn, %d misspelled paths copied" % [MoveFxSprites.RECIPES.size(), MoveFxSprites.COPIES.size()])
	_write_json(out_dir.path_join("roster.json"), {"species": roster})
	_write_json(out_dir.path_join("report.json"), {"summary": summary(roster, qa), "species": qa})
	print("  roster: %d species (%d failed); %d models and skins converted, %d reused; see report.json" % [
		roster.size(), entries.size() - roster.size(), converted, written.size() / 2 - converted])
	return ""


## One look of a species, its base or a cosmetic form, drawn with `aspects`: its scene
## models/<stem>.scn and its shiny. Returns {"files", "sidecar", "model", "shiny" (a file, or ""
## with "shiny_error"), "converted" (models and skins converted rather than reused), "written"
## (the files it keeps in models/)}, {"error"} for a look that can't be converted, or {"fatal"}
## when the build can't go on.
static func _look(stem: String, source_dir: String, folder: String, aspects: Array, converter_key: String,
		models_dir: String, previous_models: String) -> Dictionary:
	var files := CobblemonSpecies.files(source_dir, folder, aspects)
	if files.has("error"):
		return files
	var scene := _scene(stem, source_dir, folder, aspects, files, converter_key, models_dir, previous_models)
	if scene.has("error") or scene.has("fatal"):
		return scene
	var look := {"files": files, "sidecar": scene.sidecar, "model": stem + ".scn", "shiny": "",
		"converted": scene.converted, "written": {stem + ".scn": true, stem + ".json": true}}
	var shiny_files := CobblemonSpecies.files(source_dir, folder, aspects + ["shiny"])
	if shiny_files.has("error"):
		look.shiny_error = shiny_files.error
		return look
	if same_look(shiny_files, files):
		look.shiny_error = "no shiny variation"
		return look
	if not FileAccess.file_exists(shiny_files.texture):
		look.shiny_error = "shiny texture %s is missing" % shiny_files.texture.get_file()
		return look
	var shiny_stem := stem + SHINY_SUFFIX
	var shiny: Dictionary
	var ext := ".res"
	if shiny_files.geo == files.geo and shiny_files.poser == files.poser:
		shiny = _skin(shiny_stem, shiny_files, converter_key, models_dir, previous_models)
	else:
		shiny = _scene(shiny_stem, source_dir, folder, aspects + ["shiny"], shiny_files, converter_key, models_dir, previous_models)
		ext = ".scn"
	if shiny.has("fatal"):
		return shiny
	if shiny.has("error"):
		look.shiny_error = shiny.error
		return look
	look.shiny = shiny_stem + ext
	look.converted += shiny.converted
	look.written[shiny_stem + ext] = true
	look.written[shiny_stem + ".json"] = true
	return look


## Converts a look's scene into models/<stem>.scn, or reuses it when its key still matches.
## Returns {"sidecar", "converted": 0 or 1}, {"error"} or {"fatal"}.
static func _scene(stem: String, source_dir: String, folder: String, aspects: Array, files: Dictionary,
		converter_key: String, models_dir: String, previous_models: String) -> Dictionary:
	var key := _input_key(source_dir, folder, files, converter_key)
	var sidecar := _cached(stem, key, models_dir, previous_models)
	if not sidecar.is_empty():
		return {"sidecar": sidecar, "converted": 0}
	var result := CobblemonModel.convert(source_dir, folder, aspects)
	if result.has("error"):
		return result
	var err := ResourceSaver.save(result.scene, models_dir.path_join(stem + ".scn"))
	if err != OK:
		return {"fatal": "cannot save model %s (%s)" % [stem, error_string(err)]}
	sidecar = {"key": key, "report": _json_report(result.report)}
	_write_json(models_dir.path_join(stem + ".json"), sidecar)
	return {"sidecar": sidecar, "converted": 1}


## Writes a shiny skin, models/<stem>.res: the material a look wears when only its textures
## change (CobblemonModel.skin()), or reuses it when its key still matches. Returns
## {"converted": 0 or 1} or {"fatal"}.
static func _skin(stem: String, files: Dictionary, converter_key: String, models_dir: String, previous_models: String) -> Dictionary:
	var parts: PackedStringArray = [converter_key, "skin", FileAccess.get_sha256(files.texture)]
	for layer: Dictionary in files.layers:
		parts.append("layer:%s:%s" % [layer.emissive, FileAccess.get_sha256(layer.texture) if FileAccess.file_exists(layer.texture) else "missing"])
	var key := "|".join(parts).sha256_text()
	if not _cached(stem, key, models_dir, previous_models, ".res").is_empty():
		return {"converted": 0}
	var err := ResourceSaver.save(CobblemonModel.skin(files), models_dir.path_join(stem + ".res"))
	if err != OK:
		return {"fatal": "cannot save skin %s (%s)" % [stem, error_string(err)]}
	_write_json(models_dir.path_join(stem + ".json"), {"key": key})
	return {"converted": 1}


## Whether two looks' files draw the same: the same model, texture, poser and layers.
static func same_look(a: Dictionary, b: Dictionary) -> bool:
	return a.geo == b.geo and a.texture == b.texture and a.poser == b.poser and a.layers == b.layers


## Lists a look's shiny on its roster entry (`target`), or flags the species `no_shiny` and
## records why in its QA record.
static func _add_shiny(listed: Dictionary, look: Dictionary, target: Dictionary) -> void:
	if not look.shiny.is_empty():
		target.shiny = look.shiny
		return
	listed.qa.get_or_add("no_shiny", {})[look.model.get_basename()] = look.shiny_error
	if not listed.entry.flags.has("no_shiny"):
		listed.entry.flags.append("no_shiny")


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
	for problem in ["unknown_bones", "molang_errors", "molang_trailing", "unknown_names"]:
		if report.has(problem):
			flags.append(problem)
	var roster_entry := {
		"name": entry.name, "num": entry.num, "folder": entry.folder, "aspects": entry.aspects,
		"model": entry.id + ".scn", "scale": sized.scale, "height": sized.height, "radius": sized.radius, "flies": entry.flies,
		"animations": (report.get("animations", {}) as Dictionary).keys(), "poser": report.get("poser", false),
		"flags": flags, "licence": LICENCE,
	}
	var qa := {"flags": flags, "model_height": model_height, "hitbox_height": hitbox_height}
	for problem in ["unknown_bones", "molang_errors", "molang_trailing", "unknown_names", "missing_texture"]:
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


## The sidecar of a model (or, with `ext` ".res", a skin) whose key matches, moving it from the
## previous build into `models_dir` if needed; {} when it must be converted.
static func _cached(id: String, key: String, models_dir: String, previous_models: String, ext := ".scn") -> Dictionary:
	for dir in [models_dir, previous_models]:
		if dir.is_empty():
			continue
		var sidecar: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(id + ".json"))) \
			if FileAccess.file_exists(dir.path_join(id + ".json")) else null
		if not (sidecar is Dictionary and sidecar.get("key") == key and FileAccess.file_exists(dir.path_join(id + ext))):
			continue
		if dir != models_dir:
			for moved in [ext, ".json"]:
				if DirAccess.rename_absolute(dir.path_join(id + moved), models_dir.path_join(id + moved)) != OK:
					return {}
		return sidecar
	return {}


## Removes files this build didn't write or reuse, e.g. models of species or forms no longer
## in the roster, left from an older build.
static func _prune(models_dir: String, written: Dictionary) -> void:
	for file in DirAccess.get_files_at(models_dir):
		if not written.has(file):
			DirAccess.remove_absolute(models_dir.path_join(file))


## Copies a folder tree; returns the number of files, or -1 on failure.
static func _copy_tree(from: String, to: String) -> int:
	if not DirAccess.dir_exists_absolute(from) or DirAccess.make_dir_recursive_absolute(to) != OK:
		return -1
	var count := 0
	for sub in DirAccess.get_directories_at(from):
		var copied := _copy_tree(from.path_join(sub), to.path_join(sub))
		if copied < 0:
			return -1
		count += copied
	for file in DirAccess.get_files_at(from):
		if DirAccess.copy_absolute(from.path_join(file), to.path_join(file)) != OK:
			return -1
		count += 1
	return count


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
