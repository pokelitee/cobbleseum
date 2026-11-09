class_name BattleView
extends Node3D
## Plays a battle in a 3D arena (concepts_brief.md §12). User arguments (after --):
## <spec.json> [--clip-seconds=S] [--expect-checksum=HEX].
##
## The battle is run headless first so the Director can plan the whole presentation: hit-stop,
## slow motion and camera shots. Each video frame then either holds the current tick or
## advances the simulation by one. Under Movie Maker every frame is 1/30 s; otherwise frames
## follow real time. With --clip-seconds the view starts late enough to end on the knockout,
## quits when the plan ends, and exits with code 2 if the battle's checksum doesn't match
## --expect-checksum.

const DEFAULT_SPEC := "res://game/data/battles/showcase.json"
const CHECKSUM_OK := "CHECKSUM_OK"
const MODELS_DIR := "res://cache/build/cobblemon/1.8.4/models"
## Random stream id for the handheld wobble, after the simulation's own streams.
const CAMERA_WOBBLE_STREAM := 100
const PROJECTILE_COLORS := {
	"Water": Color(0.25, 0.55, 1.0), "Fire": Color(1.0, 0.45, 0.1), "Grass": Color(0.3, 0.85, 0.3),
	"Electric": Color(1.0, 0.9, 0.2), "Ice": Color(0.6, 0.95, 1.0), "Psychic": Color(1.0, 0.4, 0.7),
}

var battle: Battle
var plan: Dictionary
var _views: Array[FighterView] = []
var _projectile_meshes: Array[MeshInstance3D] = []
var _bars: Array[ColorRect] = []
var _camera: Camera3D
var _rig: CameraRig
var _portrait := false
var _event_index := 0
## Presentation position: the tick being shown and frames left before it advances.
var _tick := 0
var _hold_frames := 0
var _hold_is_hitstop := false
var _segment: Dictionary = {}
var _segment_frames := 0
var _frames_shown := 0
var _clip_mode := false
var _expected_checksum := ""
var _accumulator := 0.0


func _ready() -> void:
	var options := _parse_args(OS.get_cmdline_user_args())
	var spec: Variant = JSON.parse_string(FileAccess.get_file_as_string(options.spec))
	if not spec is Dictionary:
		return _fail("cannot read battle spec %s" % options.spec)
	var loaded := BattleData.load_showdown()
	if loaded.has("error"):
		return _fail(loaded.error)
	var created := Battle.create(spec, loaded.data, SimpleAI.pair(int(spec.seed)))
	if created.has("error"):
		return _fail(created.error)
	battle = created.battle
	plan = _plan(spec, loaded.data)
	_clip_mode = options.clip_seconds > 0.0
	_expected_checksum = options.expect_checksum

	var size := get_viewport().get_visible_rect().size
	_portrait = VideoFormat.is_portrait(size)
	_build_stage()
	for side in 2:
		var entry: Dictionary = spec.fighters[side]
		var view := FighterView.from_model(MODELS_DIR.path_join(str(entry.get("model", "")) + ".scn"))
		if view == null:
			return _fail("no converted model for '%s'; set \"model\" in the spec and run tools/assets.gd" % entry.get("model", ""))
		add_child(view)
		_views.append(view)
	_build_hud(size)
	# The wobble gets its own stream so it can't change the director's choices.
	_rig = CameraRig.new(_portrait, [_views[0].height, _views[1].height],
		SimRandom.stream(int(spec.seed), CAMERA_WOBBLE_STREAM))

	var start := _clip_start(options.clip_seconds) if _clip_mode else 0
	while battle.tick < start and not battle.is_over():
		battle.step()
	_tick = battle.tick
	_event_index = battle.events.size()
	_begin_tick()
	_sync_views()


## Runs a copy of the battle headless and plans its presentation.
func _plan(spec: Dictionary, data: BattleData) -> Dictionary:
	var preview: Battle = Battle.create(spec, data, SimpleAI.pair(int(spec.seed))).battle
	preview.run()
	var move_power := [{}, {}]
	for side in 2:
		for move in preview.fighters[side].moves:
			move_power[side][move.id] = move.power
	var max_hp := [preview.fighters[0].max_hp, preview.fighters[1].max_hp]
	return Director.plan(preview.events, preview.tick, max_hp, move_power,
		battle.random_stream(Battle.Stream.COSMETIC))


## The latest tick from which the rest of the plan fills at least `seconds` of video.
func _clip_start(seconds: float) -> int:
	var wanted := roundi(seconds * Rules.TICK_RATE)
	var total := 0
	for t in range(plan.slow.size() - 1, -1, -1):
		total += plan.slow[t] + plan.hitstop[t]
		if total >= wanted:
			return t
	return 0


func _process(delta: float) -> void:
	if battle == null:
		return
	var frames := 1
	if not _is_recording():
		_accumulator += delta
		frames = int(_accumulator * Rules.TICK_RATE)
		_accumulator -= frames / float(Rules.TICK_RATE)
	for i in frames:
		_next_frame()


## One video frame: hold the current tick, or advance to the next one.
func _next_frame() -> void:
	if _tick >= plan.slow.size():
		if _clip_mode:
			_finish()
		return
	_segment_frames += 1
	_frames_shown += 1
	if _hold_frames > 0:
		_hold_frames -= 1
	else:
		if not battle.is_over():
			battle.step()
			_play_events()
		_tick += 1
		if _tick >= plan.slow.size():
			return
		_begin_tick()
	_sync_views()


## Sets how long the current tick is held and how fast animations play meanwhile:
## frozen during hit-stop, slowed during slow motion.
func _begin_tick() -> void:
	if _tick >= plan.slow.size():
		return
	var hitstop: int = plan.hitstop[_tick]
	var slow: int = plan.slow[_tick]
	_hold_frames = hitstop + slow - 1
	_hold_is_hitstop = hitstop > 0
	for view in _views:
		view.set_time_scale(0.0 if hitstop > 0 else 1.0 / slow)
	var segment := Director.shot_for(plan.shots, _tick)
	if segment != _segment:
		_segment = segment
		_segment_frames = 0


func _finish() -> void:
	set_process(false)
	var status := 0
	if not _expected_checksum.is_empty():
		if battle.is_over() and battle.checksum() == _expected_checksum:
			# The recorder looks for this line before it accepts the rendered movie.
			print("%s %s" % [CHECKSUM_OK, battle.checksum()])
		else:
			printerr("error: rendered battle diverged from the headless run (checksum %s, expected %s)" % [battle.checksum(), _expected_checksum])
			status = 2
	get_tree().quit(status)


func _play_events() -> void:
	while _event_index < battle.events.size():
		var event: Dictionary = battle.events[_event_index]
		_event_index += 1
		match event.type:
			"windup":
				var move := _move(event.side, event.move)
				_views[event.side].play_role("physical" if move.kind == BattleMove.Kind.MELEE else "special")
			"hit":
				_views[1 - event.side].play_role("recoil")
			"faint":
				_views[event.side].play_role("faint")


func _move(side: int, move_id: String) -> BattleMove:
	for move in battle.fighters[side].moves:
		if move.id == move_id:
			return move
	return battle.fighters[side].moves[0]


func _sync_views() -> void:
	if _hold_is_hitstop and _hold_frames < plan.slow[mini(_tick, plan.slow.size() - 1)]:
		_hold_is_hitstop = false
		for view in _views:
			view.set_time_scale(1.0 / plan.slow[mini(_tick, plan.slow.size() - 1)])
	for side in 2:
		var fighter := battle.fighters[side]
		_views[side].place(fighter.position, fighter.facing)
		_bars[side].scale.x = float(fighter.hp) / fighter.max_hp
	while _projectile_meshes.size() < battle.projectiles.size():
		var mesh := MeshInstance3D.new()
		mesh.mesh = SphereMesh.new()
		mesh.mesh.radius = Rules.PROJECTILE_RADIUS
		mesh.mesh.height = Rules.PROJECTILE_RADIUS * 2
		add_child(mesh)
		_projectile_meshes.append(mesh)
	for i in _projectile_meshes.size():
		var mesh := _projectile_meshes[i]
		mesh.visible = i < battle.projectiles.size()
		if mesh.visible:
			var projectile: Dictionary = battle.projectiles[i]
			var move := battle.fighters[projectile.owner].moves[projectile.move]
			mesh.position = Vector3(projectile.position.x, 1.0, projectile.position.y)
			var material := StandardMaterial3D.new()
			material.albedo_color = PROJECTILE_COLORS.get(move.type, Color.WHITE)
			material.emission_enabled = true
			material.emission = material.albedo_color
			mesh.material_override = material
	var span := maxi(1, int(_segment.end) - int(_segment.start))
	var progress := float(_tick - int(_segment.start)) / span
	_rig.apply(_camera, _segment, battle, _segment_frames / float(Rules.TICK_RATE), progress,
		_frames_shown / float(Rules.TICK_RATE), _segment_frames == 0)


func _build_stage() -> void:
	var arena := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = Rules.ARENA_RADIUS
	disc.bottom_radius = Rules.ARENA_RADIUS
	disc.height = 0.2
	arena.mesh = disc
	arena.position.y = -0.1
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.42, 0.55, 0.38)
	arena.material_override = floor_material
	add_child(arena)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, 30, 0)
	light.shadow_enabled = true
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.53, 0.72, 0.9)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.65, 0.65, 0.7)
	add_child(environment)
	_camera = Camera3D.new()
	add_child(_camera)


## Portrait: side B (far from the camera) at the top, side A at the bottom.
## Landscape: side A top-left, side B top-right.
func _build_hud(size: Vector2) -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	var margin := 60.0
	var bar_width := size.x - 2 * margin if _portrait else size.x * 0.4
	for side in 2:
		var panel := Control.new()
		if _portrait:
			panel.position = Vector2(margin, 90 if side == 1 else size.y - 220)
		else:
			panel.position = Vector2(margin if side == 0 else size.x - margin - bar_width, 40)
		hud.add_child(panel)
		var label := Label.new()
		label.text = battle.fighters[side].name
		label.add_theme_font_size_override("font_size", 56)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 12)
		panel.add_child(label)
		var back := ColorRect.new()
		back.color = Color(0, 0, 0, 0.6)
		back.position = Vector2(0, 80)
		back.size = Vector2(bar_width, 36)
		panel.add_child(back)
		var bar := ColorRect.new()
		bar.color = Color(0.3, 0.9, 0.4)
		bar.position = Vector2(4, 84)
		bar.size = Vector2(bar_width - 8, 28)
		if not _portrait and side == 1:
			# Mirror the right-hand bar so it drains toward the centre of the screen.
			bar.pivot_offset = Vector2(bar.size.x, 0)
		panel.add_child(bar)
		_bars.append(bar)
	var credit := Label.new()
	credit.text = "Models and animations: Cobblemon (CC BY-NC 3.0)"
	credit.add_theme_font_size_override("font_size", 28)
	credit.add_theme_color_override("font_outline_color", Color.BLACK)
	credit.add_theme_constant_override("outline_size", 8)
	credit.position = Vector2(margin, size.y - 60)
	hud.add_child(credit)


func _is_recording() -> bool:
	return not Array(OS.get_cmdline_args()).filter(func(a: String) -> bool: return a.begins_with("--write-movie")).is_empty()


func _parse_args(args: PackedStringArray) -> Dictionary:
	var options := {"spec": DEFAULT_SPEC, "clip_seconds": 0.0, "expect_checksum": ""}
	for arg in args:
		if arg.begins_with("--clip-seconds="):
			options.clip_seconds = arg.get_slice("=", 1).to_float()
		elif arg.begins_with("--expect-checksum="):
			options.expect_checksum = arg.get_slice("=", 1)
		else:
			options.spec = arg
	return options


func _fail(message: String) -> void:
	printerr("error: " + message)
	get_tree().quit(1)
