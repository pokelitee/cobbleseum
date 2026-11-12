extends SceneTree
## Renders converted models for visual checks of the converter.
## Usage (needs a window, not --headless):
##   godot --path . --script res://tools/preview_model.gd -- 0009_blastoise [more folders]
##       [--animation=physical]
## Without --animation: the rest pose from four sides. With --animation=<role>: four moments of that
## role's animation from a three-quarter view. Writes cache/previews/<folder>[_<role>].png;
## previews show Cobblemon art, so they stay in the cache.

const SOURCE := "res://cache/sources/cobblemon/1.8.4"
const VIEW_SIZE := 384
## Camera yaw per view: front (the model faces -Z), left side, back, three-quarter.
const VIEWS: Array[float] = [0.0, 90.0, 180.0, 35.0]
const ANIMATION_VIEW := 35.0
const ANIMATION_MOMENTS: Array[float] = [0.0, 0.33, 0.5, 0.75]

## The project's stretch settings fix the root viewport's size, so views render here.
var _viewport: SubViewport


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(VIEW_SIZE, VIEW_SIZE)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var source := ProjectSettings.globalize_path(SOURCE)
	var out_dir := ProjectSettings.globalize_path("res://cache/previews")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var role := ""
	var folders: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--animation="):
			role = arg.trim_prefix("--animation=")
		else:
			folders.append(arg)
	var status := 0
	for folder in folders:
		var path := out_dir.path_join(folder + ("" if role.is_empty() else "_" + role) + ".png")
		var err: String = await _render(source, folder, role, path)
		if not err.is_empty():
			printerr("error: " + err)
			status = 1
	quit(status)


func _render(source: String, folder: String, role: String, path: String) -> String:
	var converted := CobblemonModel.convert(source, folder)
	if converted.has("error"):
		return converted.error
	var model: Node3D = converted.scene.instantiate()
	var player: AnimationPlayer = model.get_node("AnimationPlayer")
	var animations: Dictionary = model.get_meta("animations")
	if not role.is_empty() and not animations.has(role):
		model.free()
		return "%s has no '%s' animation (has %s)" % [folder, role, ", ".join(animations.keys())]
	var stage := _stage()
	stage.add_child(model)
	_viewport.add_child(stage)
	var bounds := _bounds(model)
	var camera: Camera3D = stage.get_node("Camera")
	var shots := VIEWS.size() if role.is_empty() else ANIMATION_MOMENTS.size()
	var sheet := Image.create(VIEW_SIZE * shots, VIEW_SIZE, false, Image.FORMAT_RGBA8)
	for i in shots:
		var yaw := deg_to_rad(VIEWS[i] if role.is_empty() else ANIMATION_VIEW)
		if not role.is_empty():
			player.play(animations[role])
			player.seek(player.current_animation_length * ANIMATION_MOMENTS[i], true)
			player.pause()
		var distance := bounds.get_longest_axis_size() * 1.6 + 0.5
		var target := bounds.get_center()
		camera.position = target + Vector3(sin(yaw), 0.35, -cos(yaw)) * distance
		camera.look_at(target)
		await process_frame
		await process_frame
		var image := _viewport.get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(image, Rect2i(0, 0, VIEW_SIZE, VIEW_SIZE), Vector2i(i * VIEW_SIZE, 0))
	stage.queue_free()
	sheet.save_png(path)
	print("%s: wrote %s" % [folder, path])
	return ""


func _stage() -> Node3D:
	var stage := Node3D.new()
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.fov = 40
	stage.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 150, 0)
	stage.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.55, 0.62, 0.7)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	stage.add_child(environment)
	return stage


func _bounds(model: Node3D) -> AABB:
	var mesh_instance: MeshInstance3D = model.get_node("Skeleton/Mesh")
	return mesh_instance.get_aabb() if mesh_instance.mesh != null else AABB(Vector3.ZERO, Vector3.ONE)
