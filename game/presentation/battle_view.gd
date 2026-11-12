class_name BattleView
extends Node3D
## Plays a battle in a 3D arena (concepts_brief.md §12). User arguments (after --):
## <spec.json> [--clip-seconds=S] [--expect-checksum=HEX] [--ai-debug]. --ai-debug shows the
## AI debug overlay from the start; F3 toggles it in the window.
##
## Instead of a spec file, SpecFlags can describe the battle: --watch=<species> [--vs=<species>]
## [--ai=<profile>] [--vs-ai=<profile>] [--seed=N] for AI against AI. --arena=<name> (or a
## spec's "arena") picks the arena (a preset in Arenas); otherwise the seed picks one that suits
## the fighters' types. The arena is part of the battle: its field's terrain (§9.8).
##
## Play mode (--play=<species> [--vs=<species>] [--ai=<profile>] [--seed=N], or a spec with
## "ai": "player"): the battle runs live, one tick per 1/30 s, since a player's choices can't
## be planned ahead. A camera follows the player's fighter, heavy hits freeze play briefly,
## a move bar shows keys and cooldowns, and the battle's intents are saved as a replay in
## recordings/replays/ that tools/record.gd can render. R starts a rematch, Esc quits.
##
## The battle is run headless first so the Director can plan the whole presentation: hit-stop,
## slow motion and camera shots. Each video frame then either holds the current tick or
## advances the simulation by one. Under Movie Maker every frame is 1/30 s; otherwise frames
## follow real time. With --clip-seconds the view plays only the window Highlights picks,
## then the credits card, and quits. Before quitting it finishes the battle off screen and
## exits with code 2 if the battle's checksum doesn't match --expect-checksum.

const DEFAULT_SPEC := "res://game/data/battles/showcase.json"
const REPLAYS_DIR := "res://recordings/replays"
## Play mode: frames the controls hint stays up, and frames after the knockout before the
## replay is saved and the rematch hint shows.
const HINT_FRAMES := 150
const END_LINGER_FRAMES := 45
const CHECKSUM_OK := "CHECKSUM_OK"
## Printed in clip mode with the window's start and end ticks, for the recorder.
const CLIP_WINDOW := "CLIP_WINDOW"
const MODELS_DIR := "res://cache/build/cobblemon/1.8.4/models"

const STAT_NAMES := {"atk": "Attack", "def": "Defense", "spa": "Sp. Atk", "spd": "Sp. Def", "spe": "Speed"}
const STATUS_CALLOUTS := {
	"brn": "Burned!", "par": "Paralyzed!", "psn": "Poisoned!", "tox": "Badly poisoned!", "slp": "Fell asleep!",
	"frz": "Frozen solid!", "confusion": "Confused!",
}
const RISE_COLOUR := Color(1.0, 0.55, 0.3)
const DROP_COLOUR := Color(0.4, 0.6, 1.0)
const HEAL_COLOUR := Color(0.45, 1.0, 0.55)
## Metres a fighter must move in a tick to play its walk clip.
const WALK_THRESHOLD := 0.01
## Random stream id for the handheld wobble, after the simulation's own streams.
const CAMERA_WOBBLE_STREAM := 100

var battle: Battle
var plan: Dictionary
## Tick where presentation stops: the plan's end, or the clip window's end.
var _end_tick := 0
var _preview_events: Array = []
var _views: Array[FighterView] = []
var _hud: Hud
var _overlay: AIOverlay
var _move_fx: MoveFX
var _sound: BattleSound
var _credits_frames := 0
var _camera: Camera3D
var _rig: CameraRig
var _fx: ImpactFX
var _portrait := false
var _event_index := 0
## Tick each side last fired a projectile, to spot ranged moves that hit as they fire.
var _fired_tick: Array[int] = [-1, -1]
## Hits landed by each side's current move, for "Hit N times!".
var _hit_counts: Array[int] = [0, 0]
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
var _arena: Arena
## Play mode state.
var _live := false
var _player_side := -1
var _player: PlayerController
var _player_camera: PlayerCamera
var _live_frames := 0
var _end_frames := 0


func _ready() -> void:
	var options := _parse_args(OS.get_cmdline_user_args())
	var spec: Variant = options.flag_spec if not options.flag_spec.is_empty() \
		else JSON.parse_string(FileAccess.get_file_as_string(options.spec))
	if spec is Dictionary and spec.has("error"):
		return _fail(spec.error)
	if not spec is Dictionary:
		return _fail("cannot read battle spec %s" % options.spec)
	var loaded := BattleData.load_all()
	if loaded.has("error"):
		return _fail(loaded.error)
	var controllers := Controllers.for_spec(spec)
	if controllers.has("error"):
		return _fail(controllers.error)
	var created := Battle.create(spec, loaded.data, controllers.controllers)
	if created.has("error"):
		return _fail(created.error)
	battle = created.battle
	for side in 2:
		if controllers.controllers[side] is PlayerController:
			_player_side = side
			_player = controllers.controllers[side]
	_live = _player_side >= 0
	if _live:
		PlayerController.ensure_input_actions()
		battle.record_intents = true
		_player_camera = PlayerCamera.new()
	else:
		plan = _plan(spec, loaded.data)
	_clip_mode = options.clip_seconds > 0.0
	_expected_checksum = options.expect_checksum

	var size := get_viewport().get_visible_rect().size
	_portrait = VideoFormat.is_portrait(size)
	_build_stage(battle.arena)
	if _player_camera != null:
		_player_camera.limit = _arena.camera_limit
	for side in 2:
		var entry: Dictionary = loaded.data.roster[battle.fighters[side].species_id]
		var view := FighterView.from_model(MODELS_DIR.path_join(entry.model), entry.scale, entry.height)
		if view == null:
			return _fail("cannot load the model %s; run tools/assets.gd" % entry.model)
		add_child(view)
		view.set_hovering("Flying" in battle.fighters[side].types or view.floats())
		_views.append(view)
	for side in 2:
		_views[side].watch(_views[1 - side])
	_hud = Hud.new()
	add_child(_hud)
	_hud.setup([battle.fighters[0].name, battle.fighters[1].name], size)
	_move_fx = MoveFX.new()
	add_child(_move_fx)
	for fighter in battle.fighters:
		for move in fighter.moves:
			_move_fx.styles[move.id] = MoveStyle.of(move.id, loaded.data.moves[move.id])
	_sound = BattleSound.new()
	add_child(_sound)
	_sound.setup([spec.fighters[0].species, spec.fighters[1].species])
	_sound.intro()
	_views[0].play_role_after("cry", 0)
	_views[1].play_role_after("cry", BattleSound.INTRO_CRY_GAP)
	_fx = ImpactFX.new()
	_fx.layer = 2  # callouts and impact frames draw over the HUD
	add_child(_fx)
	_fx.setup(_camera, size, _hud_bands(size))
	_overlay = AIOverlay.new()
	_overlay.layer = 3
	add_child(_overlay)
	_overlay.setup(controllers.controllers, [battle.fighters[0].name, battle.fighters[1].name], size, _hud_bands(size))
	_overlay.visible = options.ai_debug
	# The wobble gets its own stream so it can't change the director's choices.
	_rig = CameraRig.new(_portrait, [_views[0].height, _views[1].height],
		SimRandom.stream(int(spec.seed), CAMERA_WOBBLE_STREAM))
	_rig.limit = _arena.camera_limit

	if _live:
		var player := battle.fighters[_player_side]
		_hud.show_move_bar(player.moves.map(func(m: BattleMove) -> String: return m.name),
			player.moves.map(func(m: BattleMove) -> String: return m.type), PlayerController.MOVE_KEYS)
		_hud.show_hint("Move: WASD / stick   Dodge: Space / A   F3: AI scores")
		_event_index = 0
		for side in 2:
			_hud.set_hp(side, 1.0, true)
		return
	var start := 0
	_end_tick = plan.slow.size()
	if _clip_mode:
		var window := Highlights.choose(plan, _preview_events, [battle.fighters[0].max_hp, battle.fighters[1].max_hp],
			roundi(options.clip_seconds * Rules.TICK_RATE))
		start = window.start
		_end_tick = window.end
		print("%s %d %d" % [CLIP_WINDOW, start, _end_tick])
	while battle.tick < start and not battle.is_over():
		battle.step()
	_tick = battle.tick
	_event_index = battle.events.size()
	_begin_tick()
	_sync_views()
	for side in 2:
		var fighter := battle.fighters[side]
		_hud.set_hp(side, float(fighter.hp) / fighter.max_hp, true)
		# A clip can start mid-battle, after conditions were inflicted.
		_hud.set_status(side, fighter.status, not fighter.status.is_empty())
		_hud.set_status(side, "confusion", fighter.confusion_ticks > 0)
		_views[side].set_asleep(fighter.status == "slp")


## Runs a copy of the battle headless and plans its presentation.
func _plan(spec: Dictionary, data: BattleData) -> Dictionary:
	var preview: Battle = Battle.create(spec, data, Controllers.for_spec(spec).controllers).battle
	preview.run()
	_preview_events = preview.events
	var move_power := [{}, {}]
	for side in 2:
		for move in preview.fighters[side].moves:
			move_power[side][move.id] = move.power
	var max_hp := [preview.fighters[0].max_hp, preview.fighters[1].max_hp]
	return Director.plan(preview.events, preview.tick, max_hp, move_power,
		battle.random_stream(Battle.Stream.COSMETIC))


func _process(delta: float) -> void:
	if battle == null:
		return
	if _live:
		_player.camera_forward = _player_camera.forward()
		_player.poll()
	var frames := 1
	if not _is_recording():
		_accumulator += delta
		frames = int(_accumulator * Rules.TICK_RATE)
		_accumulator -= frames / float(Rules.TICK_RATE)
	for i in frames:
		_next_frame()


## One video frame: hold the current tick, or advance to the next one. After the plan (or
## the clip window) ends, the credits card shows for Hud.CREDITS_FRAMES before a clip finishes.
func _next_frame() -> void:
	if _live:
		_next_live_frame()
		return
	if _tick >= _end_tick:
		if _credits_frames == 0:
			_hud.show_credits()
			_fx.visible = false  # callouts stop animating here and draw above the HUD
		if _credits_frames < Hud.CREDITS_FRAMES:
			_credits_frames += 1
			_hud.next_frame()
			_sound.next_frame()
		elif _clip_mode:
			_finish()
		return
	_segment_frames += 1
	_frames_shown += 1
	if _hold_frames > 0:
		_hold_frames -= 1
	else:
		if not battle.is_over():
			_step_battle()
		_tick += 1
		if _tick >= _end_tick:
			return
		_begin_tick()
	for view in _views:
		view.next_frame()
	_fx.next_frame()
	_move_fx.next_frame()
	_hud.next_frame()
	_sound.next_frame()
	if _overlay.visible:
		_overlay.refresh()
	_fx.set_speed_lines(_segment.get("shot", -1) == Director.Shot.CLOSE_UP)
	_sync_views()


## Steps the battle one tick and tells the views how each fighter moved: walking, its speed
## over the tick (melee dashes included, for leaning and swooping), and landing from a dodge.
func _step_battle() -> void:
	var before: Array[Vector2] = [battle.fighters[0].position, battle.fighters[1].position]
	var dodging: Array[bool] = [battle.fighters[0].action == Fighter.Action.DODGE, battle.fighters[1].action == Fighter.Action.DODGE]
	battle.step()
	for side in 2:
		var fighter := battle.fighters[side]
		_views[side].set_moving(fighter.action == Fighter.Action.READY
			and fighter.position.distance_to(before[side]) > WALK_THRESHOLD)
		_views[side].set_velocity((fighter.position - before[side]) * Rules.TICK_RATE)
		if dodging[side] and fighter.action != Fighter.Action.DODGE:
			_views[side].land()
	_play_events()


## Play mode: one tick per frame, except while a hit freezes play.
func _next_live_frame() -> void:
	_live_frames += 1
	if battle.is_over():
		_end_frames += 1
		if _end_frames == END_LINGER_FRAMES:
			_save_replay()
			_hud.show_hint("R: rematch   Esc: quit")
	elif _hold_frames > 0:
		_hold_frames -= 1
		if _hold_frames == 0:
			for view in _views:
				view.set_time_scale(1.0)
	else:
		_step_battle()
	if _live_frames == HINT_FRAMES and not battle.is_over():
		_hud.show_hint("")
	for view in _views:
		view.next_frame()
	_fx.next_frame()
	_move_fx.next_frame()
	_hud.next_frame()
	_sound.next_frame()
	if _overlay.visible:
		_overlay.refresh()
	for side in 2:
		var fighter := battle.fighters[side]
		_views[side].place(fighter.position, fighter.facing, _arena.surface_at(fighter.position, fighter.ground))
		_hud.set_hp(side, float(fighter.hp) / fighter.max_hp)
	_hud.update_move_bar(battle.fighters[_player_side])
	_move_fx.sync_projectiles(battle)
	_player_camera.apply(_camera, _views[_player_side], _views[1 - _player_side])
	_update_sight()


## Saves the battle as a replay: its spec with every tick's intents per side, so it plays
## back exactly (and tools/record.gd can render it).
func _save_replay() -> void:
	var replay: Dictionary = battle.spec.duplicate(true)
	for side in 2:
		replay.fighters[side].erase("ai")
		replay.fighters[side].intents = battle.intent_log[side]
	replay.checksum = battle.checksum()
	var dir := ProjectSettings.globalize_path(REPLAYS_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	if not FileAccess.file_exists(dir.get_base_dir().path_join(".gdignore")):
		FileAccess.open(dir.get_base_dir().path_join(".gdignore"), FileAccess.WRITE).close()
	var names := "-vs-".join(battle.fighters.map(func(f: Fighter) -> String: return f.species_id))
	var path := dir.path_join("%s_%s_%d.json" % [Time.get_datetime_string_from_system().replace(":", "-"), names, int(battle.spec.seed)])
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(replay, "", false, true))
	file.close()
	print("replay saved to %s" % path)


## Sets how long the tick just shown is held and how fast animations play meanwhile:
## frozen during hit-stop, slowed during slow motion. `_tick` has already moved past the
## tick that was simulated, so its plan entry is at _tick - 1.
func _begin_tick() -> void:
	if _tick >= plan.slow.size():
		return
	var shown := _shown_tick()
	var hitstop: int = plan.hitstop[shown]
	var slow: int = plan.slow[shown]
	_hold_frames = hitstop + slow - 1
	_hold_is_hitstop = hitstop > 0
	for view in _views:
		view.set_time_scale(0.0 if hitstop > 0 else 1.0 / slow)
	var segment := Director.shot_for(plan.shots, shown)
	if segment != _segment:
		_segment = segment
		_segment_frames = 0


func _shown_tick() -> int:
	return clampi(_tick - 1, 0, plan.slow.size() - 1)


func _finish() -> void:
	set_process(false)
	var status := 0
	while not battle.is_over():
		battle.step()
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
				_views[event.side].play_role(wind_up_role(move))
				_move_fx.windup(_views[event.side], move)
				_hit_counts[event.side] = 0
				_hud.banner(event.side, move.name, move.type)
				_sound.windup(move)
			"hit":
				var defender := 1 - int(event.side)
				var move := _move(event.side, event.move)
				var share := float(event.damage) / battle.fighters[defender].max_hp
				_hit_counts[event.side] += 1
				var big: bool = event.crit or event.effectiveness > 1.0
				# Big hits get a shocked reaction from species that have one.
				_views[defender].play_role("shock" if big and _views[defender].has_clip("shock") else "recoil")
				_views[defender].take_hit(ImpactFX.IMPACT_SEQUENCE.size() if big else 0)
				_fx.on_hit(event, _views[defender], share, big)
				if _live:
					# Hit-stop in play pauses the battle itself, so it stays fair and replays exactly.
					_hold_frames = Director.HEAVY_HITSTOP_FRAMES if big else Director.HITSTOP_FRAMES
					for view in _views:
						view.set_time_scale(0.0)
				if move.kind == BattleMove.Kind.MELEE:
					_move_fx.melee(_views[event.side], _views[defender], move)
				elif _fired_tick[event.side] == int(event.tick):
					_move_fx.point_blank(_views[event.side], _views[defender], move)
				_move_fx.hit(_views[defender], move, big)
				_sound.hit(move, big)
				if big:
					_hud.shake(defender)
			"miss":
				var move := _move(event.side, event.move)
				if move.kind == BattleMove.Kind.MELEE:
					_move_fx.melee(_views[event.side], _views[1 - int(event.side)], move)
				_sound.miss(move)
			"fire":
				_fired_tick[event.side] = int(event.tick)
			"blast":
				_move_fx.blast(_views[event.side], _move(event.side, event.move))
			"multi_hit_end":
				if _hit_counts[event.side] > 1:
					_fx.announce(_views[1 - int(event.side)], "Hit %d times!" % _hit_counts[event.side], Color(1, 0.95, 0.6), 56)
			"recharge":
				_fx.announce(_views[event.side], "Must recharge!", Color(0.85, 0.85, 0.9), 48)
			"self_destruct":
				_views[event.side].take_hit()
			"landed":
				var defender := 1 - int(event.side)
				var move := _move(event.side, event.move)
				if _fired_tick[event.side] == int(event.tick):
					_move_fx.point_blank(_views[event.side], _views[defender], move)
				_move_fx.hit(_views[defender], move, false)
			"boost":
				_announce_boost(event)
				var fell: bool = (event.boosts as Dictionary).values().any(func(stages: Variant) -> bool: return int(stages) < 0)
				if fell and battle.fighters[event.side].action == Fighter.Action.READY:
					_views[event.side].play_role("angry")
			"heal":
				_move_fx.aura(_views[event.side], HEAL_COLOUR, true)
				_fx.announce(_views[event.side], "+%d" % event.amount, HEAL_COLOUR)
			"status":
				_hud.set_status(event.side, event.status, true)
				_fx.announce(_views[event.side], STATUS_CALLOUTS.get(event.status, ""),
					Hud.STATUS_BADGES[event.status][1].lightened(0.3), 60)
				if event.status == "slp":
					_views[event.side].set_asleep(true)
			"status_end":
				_hud.set_status(event.side, event.status, false)
				if event.status == "slp":
					_views[event.side].set_asleep(false)
			"status_damage":
				_fx.announce(_views[event.side], "-%d" % event.damage, Hud.STATUS_BADGES[event.status][1].lightened(0.3), 44)
			"recoil", "confusion_hit":
				_views[event.side].take_hit()
				_fx.announce(_views[event.side], "-%d" % event.damage if event.type == "recoil" else "It hurt itself in confusion!",
					Color(1, 1, 1) if event.type == "recoil" else Hud.STATUS_BADGES.confusion[1].lightened(0.3), 48)
			"stunned":
				_fx.announce(_views[event.side], "Can't move!", Hud.STATUS_BADGES.par[1].lightened(0.3), 48)
			"dodge":
				_move_fx.dodge(_views[event.side], Vector2(event.direction[0], event.direction[1]))
			"dodged":
				_fx.on_dodge(_views[event.side])
			"faint":
				_views[event.side].play_role("faint")
				_views[1 - int(event.side)].celebrate()
				_sound.faint(event.side)
				_hud.show_winner("%s wins!" % battle.fighters[1 - int(event.side)].name)
			"overtime":
				_hud.flash_title("Overtime!", Color(1.0, 0.55, 0.3))
			"time_up":
				_hud.show_winner("Time up: draw")
				for view in _views:
					view.play_role("sad")


## "Attack rose!", "Defense fell sharply!", or "Stats rose!" for several at once.
func _announce_boost(event: Dictionary) -> void:
	var changes: Dictionary = event.boosts
	var total := 0
	for stat: String in changes:
		total += int(changes[stat])
	var rising := total > 0
	var subject: String = STAT_NAMES[changes.keys()[0]] if changes.size() == 1 else "Stats"
	var amount := absi(int(changes.values()[0])) if changes.size() == 1 else 1
	var verb := ("rose" if rising else "fell") + (" sharply" if amount == 2 else (" drastically" if amount >= 3 else ""))
	_move_fx.aura(_views[event.side], RISE_COLOUR if rising else DROP_COLOUR, rising)
	_fx.announce(_views[event.side], "%s %s!" % [subject, verb], RISE_COLOUR if rising else DROP_COLOUR, 52)


## The clip a move plays on wind-up: damaging moves by category (area moves can be either),
## everything else the status clip.
static func wind_up_role(move: BattleMove) -> String:
	if not move.is_damaging():
		return "status"
	return "physical" if move.physical else "special"


func _move(side: int, move_id: String) -> BattleMove:
	for move in battle.fighters[side].moves:
		if move.id == move_id:
			return move
	return battle.fighters[side].moves[0]


## Keeps the fighters visible through cover between them and the camera.
func _update_sight() -> void:
	var chests: Array[Vector3] = []
	var grounds: Array[float] = []
	for view in _views:
		chests.append(view.global_position + Vector3.UP * view.height * 0.5)
		grounds.append(view.global_position.y)
	_arena.set_sight(chests, grounds)


func _sync_views() -> void:
	if _hold_is_hitstop and _hold_frames < plan.slow[_shown_tick()]:
		_hold_is_hitstop = false
		for view in _views:
			view.set_time_scale(1.0 / plan.slow[_shown_tick()])
	for side in 2:
		var fighter := battle.fighters[side]
		_views[side].place(fighter.position, fighter.facing, _arena.surface_at(fighter.position, fighter.ground))
		_hud.set_hp(side, float(fighter.hp) / fighter.max_hp)
	_update_sight()
	_move_fx.sync_projectiles(battle)
	var span := maxi(1, int(_segment.end) - int(_segment.start))
	var progress := float(_shown_tick() - int(_segment.start)) / span
	_rig.apply(_camera, _segment, battle, _segment_frames / float(Rules.TICK_RATE), progress,
		_frames_shown / float(Rules.TICK_RATE), _segment_frames == 0)


## The arena (its own sky, sun and weather) and the camera.
func _build_stage(arena_name: String) -> void:
	_arena = Arena.create(arena_name, int(battle.spec.seed), [battle.fighters[0].name, battle.fighters[1].name], battle.terrain)
	add_child(_arena)
	_camera = Camera3D.new()
	_camera.far = Terrain.WORLD_RADIUS * 3.0
	add_child(_camera)


## Heights of the HUD's top and bottom bands, matching the layout in Hud.setup.
func _hud_bands(size: Vector2) -> Vector2:
	return Vector2(250, 240) if _portrait else Vector2(170, 80)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_F3:
			_overlay.visible = not _overlay.visible
			_overlay.refresh()
		KEY_R:
			if _live and battle.is_over():
				get_tree().reload_current_scene()
		KEY_ESCAPE:
			if _live:
				get_tree().quit()


func _is_recording() -> bool:
	return not Array(OS.get_cmdline_args()).filter(func(a: String) -> bool: return a.begins_with("--write-movie")).is_empty()


func _parse_args(args: PackedStringArray) -> Dictionary:
	var parsed := SpecFlags.parse(args)
	var options := {"spec": DEFAULT_SPEC, "clip_seconds": 0.0, "expect_checksum": "", "ai_debug": false,
		"flag_spec": SpecFlags.to_spec(parsed.flags)}
	for arg: String in parsed.rest:
		if arg == "--ai-debug":
			options.ai_debug = true
		elif arg.begins_with("--clip-seconds="):
			options.clip_seconds = arg.get_slice("=", 1).to_float()
		elif arg.begins_with("--expect-checksum="):
			options.expect_checksum = arg.get_slice("=", 1)
		else:
			options.spec = arg
	return options


func _fail(message: String) -> void:
	printerr("error: " + message)
	get_tree().quit(1)
