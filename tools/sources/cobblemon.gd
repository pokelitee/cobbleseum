extends RefCounted
## Build step for the Cobblemon source (concepts_brief.md §7, milestone 1).
## Fully converts the showcase species into scenes, and dry-runs every species
## (geometry, clip choice and Molang compilation, without baking) into report.json.
## Milestone 2 replaces the showcase list with the whole roster and per-species caching.

const SHOWCASE: Array[String] = ["0009_blastoise", "0815_cinderace"]
## Extra files whose changes invalidate the build stamp.
const DEPENDENCIES: Array[String] = [
	"res://tools/convert/bedrock_geometry.gd",
	"res://tools/convert/bedrock_animation.gd",
	"res://tools/convert/cobblemon_model.gd",
	"res://tools/convert/cobblemon_species.gd",
	"res://tools/convert/molang.gd",
]


func build(source_dir: String, out_dir: String) -> String:
	var models_dir := out_dir.path_join("models")
	DirAccess.make_dir_recursive_absolute(models_dir)
	for folder in SHOWCASE:
		var converted := CobblemonModel.convert(source_dir, folder)
		if converted.has("error"):
			return converted.error
		var err := ResourceSaver.save(converted.scene, models_dir.path_join(folder + ".scn"))
		if err != OK:
			return "cannot save %s (%s)" % [folder, error_string(err)]
		print("  converted %s" % folder)

	var species := {}
	var failures := 0
	var resolvers := source_dir.path_join(CobblemonSpecies.BEDROCK).path_join("resolvers")
	for folder in DirAccess.get_directories_at(resolvers):
		var entry := CobblemonModel.dry_run(source_dir, folder)
		species[folder] = entry
		if entry.has("error"):
			failures += 1
	var report := {"showcase": SHOWCASE, "species": species, "summary": _summary(species)}
	var file := FileAccess.open(out_dir.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ", false))
	file.close()
	print("  dry run: %d species, %d failed; see report.json" % [species.size(), failures])
	return ""


static func _summary(species: Dictionary) -> Dictionary:
	var roles := {}
	var with_errors := 0
	for entry: Dictionary in species.values():
		if entry.has("error"):
			with_errors += 1
			continue
		for role: String in entry.get("clips", {}):
			roles[role] = roles.get(role, 0) + 1
	return {"species": species.size(), "failed": with_errors, "species_with_role": roles}
