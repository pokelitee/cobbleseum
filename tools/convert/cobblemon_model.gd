class_name CobblemonModel
extends RefCounted
## Converts one Cobblemon species folder into a packed Godot scene: the model from
## BedrockGeometry plus an AnimationPlayer holding the clips the game needs
## (concepts_brief.md §7). Clip choices are stored in the root's "clips" metadata as
## role -> animation name.

## Roles the game uses, with clip names to try when the poser doesn't name one.
const FALLBACK_CLIPS := {
	"idle": ["battle_idle", "ground_idle"],
	"walk": ["ground_walk", "ground_run"],
	"physical": ["physical"],
	"special": ["special"],
	"status": ["status"],
	"cry": ["battle_cry", "cry"],
	"recoil": ["recoil", "hurt"],
	"faint": ["faint"],
	"blink": ["blink"],
	"sleep": ["sleep"],
}
const POSER_CALL := "q\\.bedrock\\w*\\(\\s*'([^']+)'\\s*,\\s*'([^']+)'"


## Returns {"scene": PackedScene, "report": Dictionary} or {"error": String}.
static func convert(source_root: String, folder: String) -> Dictionary:
	var files := CobblemonSpecies.base_files(source_root, folder)
	if files.has("error"):
		return files
	var geo: Variant = JSON.parse_string(FileAccess.get_file_as_string(files.geo))
	if not geo is Dictionary:
		return {"error": "%s: cannot parse %s" % [folder, files.geo.get_file()]}
	var built := BedrockGeometry.build(geo, CobblemonSpecies.load_texture(files.texture), folder)
	if built.has("error"):
		return {"error": "%s: %s" % [folder, built.error]}
	var root: Node3D = built.scene
	var skeleton: Skeleton3D = root.get_node("Skeleton")
	var report := {}
	if files.texture.is_empty() or not FileAccess.file_exists(files.texture):
		report.missing_texture = files.texture

	var clips := _load_clips(source_root, folder)
	var poser := _load_poser(source_root, folder, files.poser)
	report.poser = not poser.is_empty()
	var roles := choose_clips(poser, clips.keys(), folder.get_slice("_", 1))

	var library := AnimationLibrary.new()
	for role: String in roles:
		var clip_name: String = roles[role]
		if not library.has_animation(clip_name):
			library.add_animation(clip_name, BedrockAnimation.build(
				clips[clip_name], clip_name, skeleton, root.get_meta("rest_rotations"), "Skeleton", report))
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.add_animation_library("", library)
	root.add_child(player)
	player.owner = root
	root.set_meta("clips", roles)
	report.missing_roles = FALLBACK_CLIPS.keys().filter(func(role: String) -> bool: return not roles.has(role))

	var scene := PackedScene.new()
	var err := scene.pack(root)
	root.free()
	if err != OK:
		return {"error": "%s: cannot pack scene (%s)" % [folder, error_string(err)]}
	return {"scene": scene, "report": report}


## Checks a species without baking clips: geometry, clip choice and Molang compilation.
## Returns a JSON-ready report, with "error" set when the species can't be converted.
static func dry_run(source_root: String, folder: String) -> Dictionary:
	var files := CobblemonSpecies.base_files(source_root, folder)
	if files.has("error"):
		return {"error": files.error}
	var geo: Variant = JSON.parse_string(FileAccess.get_file_as_string(files.geo))
	if not geo is Dictionary:
		return {"error": "cannot parse %s" % files.geo.get_file()}
	var built := BedrockGeometry.build(geo, null, folder)
	if built.has("error"):
		return {"error": built.error}
	var root: Node3D = built.scene
	var report := {}
	var clips := _load_clips(source_root, folder)
	var poser := _load_poser(source_root, folder, files.poser)
	var roles := choose_clips(poser, clips.keys(), folder.get_slice("_", 1))
	for clip_name: String in roles.values():
		BedrockAnimation.check(clips[clip_name], root.get_node("Skeleton"), report)
	root.free()
	var entry := {
		"clips": roles,
		"missing_roles": FALLBACK_CLIPS.keys().filter(func(role: String) -> bool: return not roles.has(role)),
		"poser": not poser.is_empty(),
		"texture_found": FileAccess.file_exists(files.texture),
	}
	for key: String in report:
		var names: Array = report[key].keys()
		names.sort()
		entry[key] = names
	return entry


## Picks a clip for each role: the poser's battle pose and named animations first,
## then the fallback names in the species' own animation group. `available` holds
## "group.clip" names.
static func choose_clips(poser: Dictionary, available: Array, default_group: String) -> Dictionary:
	var roles := {}
	var calls := RegEx.create_from_string(POSER_CALL)
	for pose_name: String in poser.get("poses", {}):
		var pose: Dictionary = poser.poses[pose_name]
		if not pose.get("isBattle", false) or not "STAND" in pose.get("poseTypes", []):
			continue
		for entry: Variant in pose.get("animations", []):
			var found := calls.search(str(entry))
			if found and not roles.has("idle") and available.has(_clip_id(found)):
				roles.idle = _clip_id(found)
		for role: String in pose.get("namedAnimations", {}):
			var found := calls.search(str(pose.namedAnimations[role]))
			if FALLBACK_CLIPS.has(role) and found and available.has(_clip_id(found)):
				roles[role] = _clip_id(found)
	var top: Variant = poser.get("animations", {})
	if top is Dictionary:
		for role: String in top:
			var found := calls.search(str(top[role]))
			if FALLBACK_CLIPS.has(role) and not roles.has(role) and found and available.has(_clip_id(found)):
				roles[role] = _clip_id(found)
	for role: String in FALLBACK_CLIPS:
		if roles.has(role):
			continue
		for clip: String in FALLBACK_CLIPS[role]:
			if available.has("%s.%s" % [default_group, clip]):
				roles[role] = "%s.%s" % [default_group, clip]
				break
	return roles


static func _clip_id(found: RegExMatch) -> String:
	return "%s.%s" % [found.get_string(1), found.get_string(2)]


## All clips in the species' animation files, keyed "group.clip" from "animation.group.clip".
static func _load_clips(source_root: String, folder: String) -> Dictionary:
	var clips := {}
	var dir := source_root.path_join(CobblemonSpecies.BEDROCK).path_join("animations").path_join(folder)
	if not DirAccess.dir_exists_absolute(dir):
		return clips  # a few species ship a model without any animations
	for file in DirAccess.get_files_at(dir):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(file)))
		if not data is Dictionary:
			continue
		for full_name: String in data.get("animations", {}):
			var parts := full_name.split(".")
			if parts.size() >= 3 and parts[0] == "animation":
				clips["%s.%s" % [parts[1], ".".join(parts.slice(2))]] = data.animations[full_name]
	return clips


static func _load_poser(source_root: String, folder: String, poser_name: String) -> Dictionary:
	if poser_name.is_empty():
		return {}
	var path := source_root.path_join(CobblemonSpecies.BEDROCK).path_join("posers").path_join(folder).path_join(poser_name + ".json")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return data if data is Dictionary else {}
