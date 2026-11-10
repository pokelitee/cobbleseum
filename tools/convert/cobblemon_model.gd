class_name CobblemonModel
extends RefCounted
## Converts one Cobblemon species folder into a packed Godot scene: the model from
## BedrockGeometry plus an AnimationPlayer holding the clips the game needs
## (concepts_brief.md §7). Clip choices are stored in the root's "clips" metadata as
## role -> animation name. Forms are converted by passing their aspects (["alolan"]).
## Resolver texture layers become extra material passes over the same mesh.

## Roles the game uses, with clip names to try when the poser doesn't name one.
const FALLBACK_CLIPS := {
	"idle": ["battle_idle", "ground_idle", "idle", "air_idle", "water_idle"],
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
## How far into the idle clip posed_bounds() samples. Rest poses are often stretched out
## (snakes lie straight), so QA compares the idle pose with the hitbox instead.
const POSED_MOMENT := 0.3
const POSER_CALL := "q\\.bedrock\\w*\\(\\s*'([^']+)'\\s*,\\s*'([^']+)'"


## Returns {"scene": PackedScene, "report": Dictionary} or {"error": String}. The report
## holds "bounds" (the rest pose's size in metres, before any scaling), "posed_bounds" (the
## size partway into the idle clip, how the model actually appears), "clips", "poser",
## "missing_roles" and any problems found while baking clips.
static func convert(source_root: String, folder: String, aspects: Array = []) -> Dictionary:
	var files := CobblemonSpecies.files(source_root, folder, aspects)
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
	_add_layers(skeleton.get_node("Mesh"), files.layers)
	var report := {}
	var mesh: MeshInstance3D = skeleton.get_node("Mesh")
	var bounds := mesh.get_aabb().size if mesh.mesh != null else Vector3.ZERO
	report.bounds = [bounds.x, bounds.y, bounds.z]
	if files.texture.is_empty() or not FileAccess.file_exists(files.texture):
		report.missing_texture = files.texture

	var clips := _load_clips(source_root, folder)
	var poser := _load_poser(source_root, folder, files.poser)
	report.poser = not poser.is_empty()
	var groups: Array[String] = [files.poser, folder.get_slice("_", 1)]
	var roles := choose_clips(poser, clips.keys(), groups)

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
	report.clips = roles
	var posed := bounds
	if roles.has("idle"):
		var idle := library.get_animation(roles.idle)
		posed = posed_bounds(skeleton, idle, idle.length * POSED_MOMENT).size
	report.posed_bounds = [posed.x, posed.y, posed.z]
	report.missing_roles = FALLBACK_CLIPS.keys().filter(func(role: String) -> bool: return not roles.has(role))

	var scene := PackedScene.new()
	var err := scene.pack(root)
	root.free()
	if err != OK:
		return {"error": "%s: cannot pack scene (%s)" % [folder, error_string(err)]}
	return {"scene": scene, "report": report}


## Chains a material pass per layer onto the mesh: emissive layers draw unshaded at full
## brightness (glowing eyes, flames), the rest shaded, both blended by the layer's alpha.
static func _add_layers(mesh_instance: MeshInstance3D, layers: Array) -> void:
	if mesh_instance.mesh == null:
		return
	var last: Material = mesh_instance.mesh.surface_get_material(0)
	for layer: Dictionary in layers:
		var texture := CobblemonSpecies.load_texture(layer.texture)
		if texture == null:
			continue
		var pass_material := StandardMaterial3D.new()
		pass_material.albedo_texture = texture
		pass_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		pass_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pass_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		pass_material.roughness = 1.0
		if layer.emissive:
			pass_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		(last as BaseMaterial3D).next_pass = pass_material
		last = pass_material


## The mesh's bounds with the skeleton posed as `animation` is at `time`, then returned
## to rest. Skinning is rigid, so each vertex follows the one bone it's bound to.
static func posed_bounds(skeleton: Skeleton3D, animation: Animation, time: float) -> AABB:
	var mesh_instance: MeshInstance3D = skeleton.get_node("Mesh")
	if mesh_instance.mesh == null:
		return AABB()
	for track in animation.get_track_count():
		var bone := skeleton.find_bone(String(animation.track_get_path(track).get_concatenated_subnames()))
		if bone < 0:
			continue
		match animation.track_get_type(track):
			Animation.TYPE_POSITION_3D:
				skeleton.set_bone_pose_position(bone, animation.position_track_interpolate(track, time))
			Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(bone, animation.rotation_track_interpolate(track, time))
			Animation.TYPE_SCALE_3D:
				skeleton.set_bone_pose_scale(bone, animation.scale_track_interpolate(track, time))
	var skin := mesh_instance.skin
	var skinning: Array[Transform3D] = []
	for bind in skin.get_bind_count():
		var bone := skeleton.find_bone(skin.get_bind_name(bind))
		skinning.append(skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bind) if bone >= 0 else Transform3D.IDENTITY)
	var arrays := mesh_instance.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var influences := bones.size() / maxi(vertices.size(), 1)
	var box := AABB(skinning[bones[0]] * vertices[0], Vector3.ZERO)
	for i in vertices.size():
		box = box.expand(skinning[bones[i * influences]] * vertices[i])
	skeleton.reset_bone_poses()
	return box


## Picks a clip for each role: the poser's battle standing pose (else any standing pose)
## and named animations first, then the fallback names in each of `groups` (the poser's,
## the species') and then any other animation group the files hold. `available` holds
## "group.clip" names. Forms often have a poser of their own (gourgeist_large) but use the
## species' animations (gourgeist).
static func choose_clips(poser: Dictionary, available: Array, groups: Array[String]) -> Dictionary:
	var roles := {}
	var calls := RegEx.create_from_string(POSER_CALL)
	var standing: Array[Dictionary] = []
	var battle_standing: Array[Dictionary] = []
	for pose_name: String in poser.get("poses", {}):
		var pose: Dictionary = poser.poses[pose_name]
		if "STAND" in pose.get("poseTypes", []):
			(battle_standing if pose.get("isBattle", false) else standing).append(pose)
	for pose: Dictionary in (battle_standing if not battle_standing.is_empty() else standing):
		for entry: Variant in pose.get("animations", []):
			var found := calls.search(str(entry))
			if found and not roles.has("idle") and available.has(_clip_id(found)):
				roles.idle = _clip_id(found)
	for pose: Dictionary in battle_standing:
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
	var search: Array[String] = []
	for group in groups:
		if not group.is_empty() and not search.has(group):
			search.append(group)
	var others: Array[String] = []
	for clip_id: String in available:
		var group := clip_id.get_slice(".", 0)
		if not search.has(group) and not others.has(group):
			others.append(group)
	others.sort()
	search.append_array(others)
	for role: String in FALLBACK_CLIPS:
		if roles.has(role):
			continue
		for clip: String in FALLBACK_CLIPS[role]:
			for group in search:
				if available.has("%s.%s" % [group, clip]):
					roles[role] = "%s.%s" % [group, clip]
					break
			if roles.has(role):
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
