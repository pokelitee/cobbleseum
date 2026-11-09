extends SceneTree
## Renders converted models from four sides for visual checks of the converter.
## Usage (needs a window, not --headless):
##   godot --path . --script res://tools/preview_model.gd -- 0009_blastoise [0815_cinderace ...]
## Writes cache/previews/<folder>.png. Previews show Cobblemon art, so they stay in the cache.

const SOURCE := "res://cache/sources/cobblemon/1.8.4"
const VIEW_SIZE := 384
## Camera yaw per view: front (the model faces -Z), left side, back, three-quarter.
const VIEWS: Array[float] = [0.0, 90.0, 180.0, 35.0]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(VIEW_SIZE, VIEW_SIZE)
	var source := ProjectSettings.globalize_path(SOURCE)
	var out_dir := ProjectSettings.globalize_path("res://cache/previews")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var status := 0
	for folder in OS.get_cmdline_user_args():
		var err: String = await _render(source, folder, out_dir.path_join(folder + ".png"))
		if not err.is_empty():
			printerr("error: " + err)
			status = 1
	quit(status)


func _render(source: String, folder: String, path: String) -> String:
	var files := CobblemonSpecies.base_files(source, folder)
	if files.has("error"):
		return files.error
	var geo: Variant = JSON.parse_string(FileAccess.get_file_as_string(files.geo))
	if not geo is Dictionary:
		return "%s: cannot parse %s" % [folder, files.geo]
	var built := BedrockGeometry.build(geo, CobblemonSpecies.load_texture(files.texture), folder)
	if built.has("error"):
		return "%s: %s" % [folder, built.error]
	var model: Node3D = built.scene
	var stage := _stage()
	stage.add_child(model)
	root.add_child(stage)
	var bounds := _bounds(model)
	var camera: Camera3D = stage.get_node("Camera")
	var sheet := Image.create(VIEW_SIZE * VIEWS.size(), VIEW_SIZE, false, Image.FORMAT_RGBA8)
	for i in VIEWS.size():
		var yaw := deg_to_rad(VIEWS[i])
		var distance := bounds.get_longest_axis_size() * 1.6 + 0.5
		var target := bounds.get_center()
		camera.position = target + Vector3(sin(yaw), 0.35, -cos(yaw)) * distance
		camera.look_at(target)
		await process_frame
		await process_frame
		var image := root.get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(image, Rect2i(0, 0, VIEW_SIZE, VIEW_SIZE), Vector2i(i * VIEW_SIZE, 0))
	stage.queue_free()
	sheet.save_png(path)
	print("%s: wrote %s (bounds %s)" % [folder, path, bounds])
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
