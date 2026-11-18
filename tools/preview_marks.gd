extends SceneTree
## Renders battlefield marks (BattleMarks, concepts_brief.md §12.5) on arenas for visual checks.
## Usage (needs a window, not --headless):
##   godot --path . --script res://tools/preview_marks.gd -- [arena ...] [--weather=rain]
##       [--surge=electric] [--worn]
## With no arenas, every preset. Two fighters stand 6 m apart on a field marked with one of
## each kind (scorch for Fire, Electric and Psychic, frost, splash for Water and Poison, cracks,
## a scuff, a fiery crater and a quake's cracks, fresh, their glows cooling); --worn adds marks
## up to the cap, as an arena looks by the knockout. The battle's wide shot and an
## over-the-shoulder shot are captured in landscape and vertical to
## cache/previews/marks_<arena>[_<weather>][_<surge>].png. Previews show Cobblemon art, so
## they stay in the cache.

const SPECIES: Array[String] = ["garchomp", "indeedee"]
const GAP := 6.0
const LANDSCAPE := Vector2i(960, 540)
const PORTRAIT := Vector2i(540, 960)
## Frames run before the shot, so weather and surges fade in and fresh glows cool a little.
const SETTLE_FRAMES := 40
## [style, type, melee, area, share, big, x, z]: one of each kind around the fighters.
const SHOWCASE := [
	["orb", "Fire", false, false, 0.25, false, -1.6, 1.6],
	["bolt", "Electric", false, false, 0.15, false, -0.3, 2.4],
	["mind", "Psychic", false, false, 0.2, true, 1.2, 1.4],
	["beam", "Ice", false, false, 0.3, false, 2.6, 2.4],
	["stream", "Water", false, false, 0.2, false, -3.2, 2.6],
	["orb", "Poison", false, false, 0.1, false, 4.0, 0.6],
	["bullet", "Rock", false, false, 0.2, false, -4.2, 0.4],
	["punch", "Fighting", true, false, 0.2, false, 3.0, 0.0],
	["orb", "Fire", false, true, 0.0, false, 0.0, -1.2],
	["quake", "Ground", false, true, 0.0, false, -3.0, -3.5],
]
const WORN_TYPES: Array[String] = ["Fire", "Water", "Electric", "Ice", "Normal", "Rock", "Grass", "Dark", "Fighting"]
const WORN_STYLES: Array[String] = ["orb", "beam", "punch", "slash", "bolt", "stream", "skyfall"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var loaded := BattleData.load_all()
	if loaded.has("error"):
		printerr("error: " + loaded.error)
		return quit(1)
	var arenas: Array[String] = []
	var options := {"weather": "", "surge": "", "worn": false}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--weather="):
			options.weather = arg.get_slice("=", 1)
		elif arg.begins_with("--surge="):
			options.surge = arg.get_slice("=", 1)
		elif arg == "--worn":
			options.worn = true
		elif not Arenas.preset(arg).is_empty():
			arenas.append(arg)
		else:
			printerr("error: unknown argument '%s'" % arg)
			return quit(1)
	if not options.surge.is_empty() and not ArenaSurge.COLOURS.has(options.surge):
		printerr("error: unknown surge '%s'" % options.surge)
		return quit(1)
	if arenas.is_empty():
		arenas.assign(Arenas.names())
	var out_dir := ProjectSettings.globalize_path("res://cache/previews")
	DirAccess.make_dir_recursive_absolute(out_dir)
	for arena_name in arenas:
		var sheet := Image.create(LANDSCAPE.x * 2 + PORTRAIT.x * 2, PORTRAIT.y, false, Image.FORMAT_RGBA8)
		var x := 0
		for size: Vector2i in [LANDSCAPE, PORTRAIT]:
			for shot in ["wide", "shoulder"]:
				var image: Image = await _shot(loaded.data, arena_name, options, size, shot)
				sheet.blit_rect(image, Rect2i(Vector2i.ZERO, size), Vector2i(x, 0))
				x += size.x
		var suffix := "".join([options.weather, options.surge, "worn" if options.worn else ""].filter(
			func(part: String) -> bool: return not part.is_empty()).map(func(part: String) -> String: return "_" + part))
		var path := out_dir.path_join("marks_%s%s.png" % [arena_name, suffix])
		sheet.save_png(path)
		print("wrote " + path)
	quit(0)


func _shot(data: BattleData, arena_name: String, options: Dictionary, size: Vector2i, shot: String) -> Image:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	var arena := Arena.create(arena_name, 1)
	viewport.add_child(arena)
	var marks := BattleMarks.new()
	viewport.add_child(marks)
	marks.setup(1, arena)
	var key := 0
	if options.worn:
		var random := SimRandom.new(5)
		for i in BattleMarks.CAP - SHOWCASE.size():
			var type: String = WORN_TYPES[random.next_u32() % WORN_TYPES.size()]
			var style: String = WORN_STYLES[random.next_u32() % WORN_STYLES.size()]
			var at := Vector2.from_angle(random.range_float(0, TAU)) * random.range_float(0.5, 7.0)
			var description := BattleMarks.describe(style, type, style in MoveStyle.MELEE, false, random.range_float(0.05, 0.35), false)
			marks.add(description, type, at, 0.0, Vector2.from_angle(random.range_float(0, TAU)), key, true)
			key += 1
	for entry: Array in SHOWCASE:
		var description := BattleMarks.describe(entry[0], entry[1], entry[2], entry[3], entry[4], entry[5])
		marks.add(description, entry[1], Vector2(entry[6], entry[7]), 0.0, Vector2.RIGHT, key)
		key += 1
	var heights: Array[float] = []
	for side in 2:
		var entry: Dictionary = data.roster[SPECIES[side]]
		var view := FighterView.from_model(BattleView.MODELS_DIR.path_join(entry.model), entry.scale, entry.height)
		viewport.add_child(view)
		var x := GAP * (side - 0.5)
		view.place(Vector2(x, 0), Vector2(-signf(x), 0), arena.surface_at(Vector2(x, 0), 0.0))
		heights.append(entry.height)
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
	if not options.weather.is_empty():
		arena.weather.show_weather(options.weather)
	if not options.surge.is_empty():
		arena.surge.show_surge(options.surge)
	for frame in SETTLE_FRAMES:
		arena.weather.next_frame()
		arena.surge.next_frame()
		marks.next_frame()
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	viewport.queue_free()
	return image
