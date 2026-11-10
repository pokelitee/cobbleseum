extends SceneTree
## Renders roster species as they appear in battle, for converter QA (concepts_brief.md §7.5).
## Usage (needs a window, not --headless):
##   godot --path . --script res://tools/preview_roster.gd -- [species ...] [--flag=bounds_mismatch]
## Each species is shown at its roster scale, partway into its idle clip, beside an outline of
## its hitbox capsule, from a camera framed on the hitbox (not the model, which may be
## wrong). Writes one contact sheet, cache/previews/roster_<name>.png, labelled by tile order
## in the printed list; previews show Cobblemon art, so they stay in the cache.

const TILE := 256
const COLUMNS := 8
const IDLE_MOMENT := 0.3

var _viewport: SubViewport


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var loaded := BattleData.load_all()
	if loaded.has("error"):
		printerr("error: " + loaded.error)
		return quit(1)
	var roster: Dictionary = loaded.data.roster
	var ids: Array[String] = []
	var flag := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--flag="):
			flag = arg.trim_prefix("--flag=")
		elif roster.has(arg):
			ids.append(arg)
		else:
			printerr("error: '%s' is not in the roster" % arg)
			return quit(1)
	if not flag.is_empty():
		for id: String in roster:
			if flag in roster[id].flags:
				ids.append(id)
	if ids.is_empty():
		printerr("error: name species or pass --flag=<qa flag>")
		return quit(1)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(TILE, TILE)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var rows := ceili(ids.size() / float(COLUMNS))
	var sheet := Image.create(TILE * mini(COLUMNS, ids.size()), TILE * rows, false, Image.FORMAT_RGBA8)
	for i in ids.size():
		print("%3d %s" % [i + 1, ids[i]])
		var image: Image = await _render(roster[ids[i]])
		sheet.blit_rect(image, Rect2i(0, 0, TILE, TILE), Vector2i((i % COLUMNS) * TILE, (i / COLUMNS) * TILE))
	var name := flag if not flag.is_empty() else ids[0]
	var path := ProjectSettings.globalize_path("res://cache/previews").path_join("roster_%s.png" % name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	sheet.save_png(path)
	print("wrote %s" % path)
	quit(0)


func _render(entry: Dictionary) -> Image:
	var stage := Node3D.new()
	_viewport.add_child(stage)
	var view := FighterView.from_model(BattleView.MODELS_DIR.path_join(entry.model), entry.scale, entry.height)
	stage.add_child(view)
	view.place(Vector2.ZERO, Vector2(1, 0.6).normalized())
	var player: AnimationPlayer = view.find_child("AnimationPlayer", true, false)
	if player.current_animation != "":
		player.seek(player.current_animation_length * IDLE_MOMENT, true)
		player.pause()
	stage.add_child(_capsule(entry.radius, entry.height))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	stage.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.55, 0.62, 0.7)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.65, 0.65, 0.7)
	stage.add_child(environment)
	var camera := Camera3D.new()
	camera.fov = 40
	stage.add_child(camera)
	camera.make_current()
	var size := maxf(entry.height, entry.radius * 2.0)
	camera.look_at_from_position(Vector3(0.6, 0.45, 1.0).normalized() * size * 3.2 + Vector3.UP * entry.height * 0.5,
		Vector3.UP * entry.height * 0.5)
	await process_frame
	await process_frame
	await process_frame
	var image := _viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	stage.queue_free()
	await process_frame
	return image


## The hitbox as a wireframe-like translucent capsule.
static func _capsule(radius: float, height: float) -> MeshInstance3D:
	var capsule := CapsuleMesh.new()
	capsule.radius = radius
	capsule.height = maxf(height, radius * 2.0)
	var instance := MeshInstance3D.new()
	instance.mesh = capsule
	instance.position = Vector3.UP * capsule.height * 0.5
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1, 0.3, 0.3, 0.18)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = material
	return instance
