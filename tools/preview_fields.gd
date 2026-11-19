extends SceneTree
## Renders each field and side condition's look on an arena (FieldLooks, concepts_brief.md §9.11)
## for visual checks.
## Usage (needs a window, not --headless):
##   godot --path . --script res://tools/preview_fields.gd -- [--arena=stadium] [condition ...]
## Two fighters stand 6 m apart. For each condition (Trick Room, Gravity, the rooms, Tailwind on
## the left fighter's side), the battle's wide shot and an over-the-shoulder shot are captured in
## landscape and vertical, once it has faded in, to cache/previews/field_<arena>_<condition>.png.
## Previews show Cobblemon art, so they stay in the cache.

const SPECIES: Array[String] = ["garchomp", "indeedee"]
const GAP := 6.0
const LANDSCAPE := Vector2i(960, 540)
const PORTRAIT := Vector2i(540, 960)
## Frames run before the shot: the condition fades in and its particles spread.
const SETTLE_FRAMES := 90


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var loaded := BattleData.load_all()
	if loaded.has("error"):
		printerr("error: " + loaded.error)
		return quit(1)
	var arena_name := "stadium"
	var names: Array[String] = []
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--arena="):
			arena_name = arg.get_slice("=", 1)
		elif FieldLooks.COLOURS.has(arg):
			names.append(arg)
		else:
			printerr("error: unknown argument '%s'" % arg)
			return quit(1)
	if Arenas.preset(arena_name).is_empty():
		printerr("error: unknown arena '%s'" % arena_name)
		return quit(1)
	if names.is_empty():
		names.assign(FieldLooks.COLOURS.keys())
	var out_dir := ProjectSettings.globalize_path("res://cache/previews")
	DirAccess.make_dir_recursive_absolute(out_dir)
	for name in names:
		var sheet := Image.create(LANDSCAPE.x * 2 + PORTRAIT.x * 2, PORTRAIT.y, false, Image.FORMAT_RGBA8)
		var x := 0
		for size: Vector2i in [LANDSCAPE, PORTRAIT]:
			for shot in ["wide", "shoulder"]:
				var image: Image = await _shot(loaded.data, arena_name, name, size, shot)
				sheet.blit_rect(image, Rect2i(Vector2i.ZERO, size), Vector2i(x, 0))
				x += size.x
		var path := out_dir.path_join("field_%s_%s.png" % [arena_name, name])
		sheet.save_png(path)
		print("wrote " + path)
	quit(0)


func _shot(data: BattleData, arena_name: String, name: String, size: Vector2i, shot: String) -> Image:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	var arena := Arena.create(arena_name, 1)
	viewport.add_child(arena)
	var heights: Array[float] = []
	var views: Array[FighterView] = []
	for side in 2:
		var entry: Dictionary = data.roster[SPECIES[side]]
		var view := FighterView.from_model(BattleView.MODELS_DIR.path_join(entry.model), entry.scale, entry.height)
		viewport.add_child(view)
		var x := GAP * (side - 0.5)
		view.place(Vector2(x, 0), Vector2(-signf(x), 0), arena.surface_at(Vector2(x, 0), 0.0))
		heights.append(entry.height)
		views.append(view)
	var portrait := size.y > size.x
	var camera := Camera3D.new()
	camera.far = Terrain.WORLD_RADIUS * 3.0
	viewport.add_child(camera)
	camera.make_current()
	# The CameraRig's wide and over-the-shoulder shots for fighters about this tall.
	var k := clampf(maxf(heights[0], heights[1]) / CameraRig.REFERENCE_HEIGHT, 0.6, 2.2)
	var back := (1.3 if portrait else 1.0) * k
	var lift := (0.6 if portrait else 0.0) * k
	camera.fov = (45.0 if shot == "wide" else 50.0) + (8.0 if portrait else 0.0)
	if shot == "wide":
		var distance := (3.4 if not portrait else 4.0) * k + GAP * 0.6
		camera.look_at_from_position(Vector3(0, 1.8 * k + lift, distance * (1.3 if portrait else 1.0)), Vector3(0, k, 0))
	else:
		var me := Vector3(-GAP * 0.5, 0, 0)
		camera.look_at_from_position(me + Vector3(-2.4 * back, 1.6 * k + lift, 2.0 * back), Vector3(GAP * 0.5, heights[1] * 0.5, 0))
	var conditions := ArenaConditions.new()
	if name == "tailwind":
		conditions.sides[0][name] = 100
	else:
		conditions.field[name] = 100
	var looks := FieldLooks.new()
	viewport.add_child(looks)
	looks.setup(1)
	for frame in SETTLE_FRAMES:
		looks.sync(conditions, views)
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	viewport.queue_free()
	return image
