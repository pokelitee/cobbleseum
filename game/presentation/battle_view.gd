class_name BattleView
extends Node3D
## Plays a battle in a 3D arena with a portrait camera and HP bars (concepts_brief.md §12).
## User arguments (after --): <spec.json> [--from-tick=N] [--until-tick=N] [--expect-checksum=HEX].
## The simulation advances one tick per video frame under Movie Maker and in real time
## otherwise; ticks before --from-tick run instantly without drawing. With --until-tick the
## view quits at that tick of presentation time (which keeps counting after the battle ends),
## exiting with code 2 if the battle's checksum doesn't match --expect-checksum.

const DEFAULT_SPEC := "res://game/data/battles/showcase.json"
const CHECKSUM_OK := "CHECKSUM_OK"
const MODELS_DIR := "res://cache/build/cobblemon/1.8.4/models"
const CAMERA_DISTANCE := 6.0
const CAMERA_HEIGHT := 4.0
## Angle between the camera and the line from side B to side A, in radians.
const CAMERA_ANGLE := deg_to_rad(65.0)
const PROJECTILE_COLORS := {
	"Water": Color(0.25, 0.55, 1.0), "Fire": Color(1.0, 0.45, 0.1), "Grass": Color(0.3, 0.85, 0.3),
	"Electric": Color(1.0, 0.9, 0.2), "Ice": Color(0.6, 0.95, 1.0), "Psychic": Color(1.0, 0.4, 0.7),
}

var battle: Battle
var _views: Array[FighterView] = []
var _projectile_meshes: Array[MeshInstance3D] = []
var _bars: Array[ColorRect] = []
var _camera: Camera3D
var _camera_axis := Vector2(0, 1)
var _event_index := 0
## Presentation time in ticks since the battle started, including ticks shown after it ended.
var _clock := 0
var _stop_tick := -1
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
	_stop_tick = options.until_tick
	_expected_checksum = options.expect_checksum

	_build_stage()
	for side in 2:
		var entry: Dictionary = spec.fighters[side]
		var view := FighterView.from_model(MODELS_DIR.path_join(str(entry.get("model", "")) + ".scn"))
		if view == null:
			return _fail("no converted model for '%s'; set \"model\" in the spec and run tools/assets.gd" % entry.get("model", ""))
		add_child(view)
		_views.append(view)
	_build_hud(spec)

	while battle.tick < options.from_tick and not battle.is_over():
		battle.step()
	_clock = battle.tick
	_event_index = battle.events.size()
	_sync_views(true)


func _process(delta: float) -> void:
	if battle == null:
		return
	var ticks := 1
	if not _is_recording():
		_accumulator += delta
		ticks = int(_accumulator * Rules.TICK_RATE)
		_accumulator -= ticks / float(Rules.TICK_RATE)
	for i in ticks:
		_advance()


## One tick of presentation time. After the battle ends, time keeps running (for the faint
## and the tail of the clip) while the simulation stays still.
func _advance() -> void:
	_clock += 1
	if not battle.is_over():
		battle.step()
		_play_events()
	_sync_views(false)
	if _stop_tick >= 0 and _clock >= _stop_tick:
		_finish()


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


func _sync_views(snap: bool) -> void:
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
	_update_camera(snap)


## Raised, at an angle across the line between the fighters with side A nearer the camera:
## steep enough that A never hides B in close combat, while both still fit a portrait frame.
## The direction follows the fighters' line only slowly so the shot doesn't swing around.
func _update_camera(snap: bool) -> void:
	var a := battle.fighters[0].position
	var b := battle.fighters[1].position
	var middle := (a + b) * 0.5
	var axis := (b - a).normalized() if a.distance_to(b) > 0.01 else Vector2(0, 1)
	_camera_axis = axis if snap else _camera_axis.slerp(axis, 0.02).normalized()
	var across := Vector2(_camera_axis.y, -_camera_axis.x)
	var direction := (-_camera_axis * cos(CAMERA_ANGLE) + across * sin(CAMERA_ANGLE)).normalized()
	var distance := CAMERA_DISTANCE + a.distance_to(b) * 0.6
	var eye := middle + direction * distance
	var target := Vector3(eye.x, CAMERA_HEIGHT, eye.y)
	_camera.position = target if snap else _camera.position.lerp(target, 0.1)
	_camera.look_at(Vector3(middle.x, 1.5, middle.y), Vector3.UP)


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
	_camera.fov = 55
	add_child(_camera)


## Side B (far from the camera) at the top, side A at the bottom.
func _build_hud(spec: Dictionary) -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	for side in 2:
		var top := side == 1
		var panel := Control.new()
		panel.position = Vector2(60, 90 if top else 1700)
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
		back.size = Vector2(960, 36)
		panel.add_child(back)
		var bar := ColorRect.new()
		bar.color = Color(0.3, 0.9, 0.4)
		bar.position = Vector2(4, 84)
		bar.size = Vector2(952, 28)
		panel.add_child(bar)
		_bars.append(bar)
	var credit := Label.new()
	credit.text = "Models and animations: Cobblemon (CC BY-NC 3.0)"
	credit.add_theme_font_size_override("font_size", 28)
	credit.add_theme_color_override("font_outline_color", Color.BLACK)
	credit.add_theme_constant_override("outline_size", 8)
	credit.position = Vector2(60, 1860)
	hud.add_child(credit)


func _is_recording() -> bool:
	return not Array(OS.get_cmdline_args()).filter(func(a: String) -> bool: return a.begins_with("--write-movie")).is_empty()


func _parse_args(args: PackedStringArray) -> Dictionary:
	var options := {"spec": DEFAULT_SPEC, "from_tick": 0, "until_tick": -1, "expect_checksum": ""}
	for arg in args:
		if arg.begins_with("--from-tick="):
			options.from_tick = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--until-tick="):
			options.until_tick = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--expect-checksum="):
			options.expect_checksum = arg.get_slice("=", 1)
		else:
			options.spec = arg
	return options


func _fail(message: String) -> void:
	printerr("error: " + message)
	get_tree().quit(1)
