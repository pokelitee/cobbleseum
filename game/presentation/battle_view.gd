class_name BattleView
extends Node3D
## Plays a battle in a 3D arena (concepts_brief.md §12). User arguments (after --):
## <spec.json> [--clip-seconds=S] [--expect-checksum=HEX] [--ai-debug] [--mesh-fx]. --ai-debug
## shows the AI debug overlay from the start; F3 toggles it in the window. Moves draw in
## Cobblemon's style (CobblemonMoveFX) when the native runtime and the cached effects are there;
## --mesh-fx, or either one missing, draws our mesh styles instead.
##
## Instead of a spec file, SpecFlags can describe the battle: --watch=<species> [--vs=<species>]
## [--ai=<profile>] [--vs-ai=<profile>] [--seed=N] for AI against AI. --arena=<name> (or a
## spec's "arena") picks the arena (a preset in Arenas); otherwise the seed picks one that suits
## the fighters' types. The arena is part of the battle: its field's terrain (§9.8).
## --shiny=a|b|both|none, --form=<form> and --vs-form=<form> set how the fighters look; the seed
## rolls what they leave out (Appearance). A spec's fighters may say the same with "shiny" and
## "form". A shiny sparkles as the battle opens and has a sparkle on its name plate.
##
## Play mode (--play=<species> [--vs=<species>] [--ai=<profile>] [--seed=N], or a spec with
## "ai": "player"): the battle runs live, one tick per 1/30 s, since a player's choices can't
## be planned ahead. A camera follows the player's fighter, heavy hits freeze play briefly,
## a move bar shows keys and cooldowns, and the battle spec is saved with every tick's intents
## and the rules and data versions in recordings/specs/, which tools/record.gd can render.
## After the battle in the window (play or watch), R or a button starts a rematch and Esc or a
## button goes back to the setup screen (SetupScreen); Esc goes back there during a battle too.
##
## The battle is run headless first so the Director can plan the whole presentation: hit-stop,
## slow motion and camera shots. Each video frame then either holds the current tick or
## advances the simulation by one. Under Movie Maker every frame is 1/30 s; otherwise frames
## follow real time, and SmoothMotion draws the fighters, camera and projectiles between them
## at the display's rate. After a knockout, the instant replay re-shows it from a second copy of
## the battle (a replay of the spec, skipped ahead), so the battle itself is never stepped
## back or again. With --clip-seconds the view plays only the window Highlights picks, then
## the credits card, and quits. Before quitting it finishes the battle off screen and
## exits with code 2 if the battle's checksum doesn't match --expect-checksum.

const DEFAULT_SPEC := "res://game/data/battles/showcase.json"
## The view's own options, besides the battle flags (SpecFlags).
const OPTIONS: Array[String] = ["ai-debug", "mesh-fx", "cobblemon-fx", "clip-seconds", "expect-checksum"]
const HELP := """Cobbleseum: real-time battles with Cobblemon's models and Showdown's data.

Usage: godot --path . [-- <spec.json> | <battle flags>] [options]
With neither, the setup screen opens; with only options, the showcase battle plays.

  <spec.json>              a battle spec, or a play-mode battle saved in recordings/specs/
  --ai-debug               starts with the AI debug overlay on (F3 toggles it)
  --mesh-fx                draws our mesh move styles instead of Cobblemon's effects

%s

%s

In play mode: WASD or arrows move, Space dodges, J K L I or 1-4 use moves, G guards, hold
Shift to feint. After a battle, R starts a rematch; Esc goes back to the setup screen.
Recording clips: tools/record.gd (--help there)."""
const SPECS_DIR := "res://recordings/specs"
## Play mode: frames the controls hint stays up, and frames after the knockout before the
## battle spec is saved and the rematch hint shows.
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
## The "Blocked!" and "Parried!" callouts over a fighter whose guard stopped a hit.
const GUARD_CALLOUT := Color(0.6, 0.85, 1.0)
## An ability's name over the fighter when it takes effect.
const ABILITY_CALLOUT := Color(1.0, 0.85, 0.45)
## A held item's name over the fighter when it takes effect or is used up.
const ITEM_CALLOUT := Color(0.75, 1.0, 0.7)
## Weather (§9.11): each one's colour (the HUD's pill, callouts) and what's said when it starts
## and ends.
const WEATHER_COLOURS := {"rain": Color(0.4, 0.65, 1.0), "sun": Color(1.0, 0.68, 0.25),
	"sand": Color(0.85, 0.7, 0.45), "snow": Color(0.78, 0.9, 1.0)}
## The HUD pill's short name for each weather.
const WEATHER_PILLS := {"rain": "Rain", "sun": "Sun", "sand": "Sand", "snow": "Snow"}
const WEATHER_STARTS := {"rain": "It started to rain!", "sun": "The sunlight turned harsh!",
	"sand": "A sandstorm kicked up!", "snow": "It started to snow!"}
const WEATHER_ENDS := {"rain": "The rain stopped.", "sun": "The sunlight faded.",
	"sand": "The sandstorm subsided.", "snow": "The snow stopped."}
## Surges: what's said when each starts and ends (colours from ArenaSurge).
const SURGE_STARTS := {"electric": "The ground crackles with electricity!", "grassy": "Grass grew over the field!",
	"misty": "Mist swirled over the field!", "psychic": "The field turned weird!"}
const SURGE_ENDS := {"electric": "The electricity faded.", "grassy": "The grass withered away.",
	"misty": "The mist cleared.", "psychic": "The weirdness faded."}
## Metres a fighter must move in a tick to play its walk animation.
const WALK_THRESHOLD := 0.01
## Hits taking at least this share of the defender's HP (or big ones) make the crowd cheer;
## a knockout holds its loudest cheer this many frames.
const CHEER_SHARE := 0.15
const KNOCKOUT_CHEER_FRAMES := 90
## The crowd's cheer when the instant replay shows the knockout again.
const REPLAY_CHEER := 0.6
## Random stream id for the handheld wobble, after the simulation's own streams.
const CAMERA_WOBBLE_STREAM := 100
## Seeds the choice of watchers in the stands, after the simulation's streams.
const WATCHER_STREAM := 101
## Picks the music track and its variants, after the simulation's streams.
const MUSIC_STREAM := 102

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
var _music: BattleMusic
## The crowd's sound in a coliseum, the field's ambience in the open.
var _arena_sound: ArenaSound
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
## Spectators in the stands (none in the open).
var _crowd: Crowd
## Play mode state.
var _live := false
var _player_side := -1
var _player: PlayerController
var _player_camera: PlayerCamera
var _live_frames := 0
var _victory_shown := false
var _end_frames := 0
## The instant replay: a copy of the battle stepped to the replay's first tick, the battle
## and event index it stands in for (set once it starts), the tick it is showing and the
## frames left on that tick.
var _replay_battle: Battle
var _main_battle: Battle
var _main_event_index := 0
var _replay_tick := 0
var _replay_hold := 0
var _replaying := false
## The next of the plan's captions to show.
var _caption_index := 0
## The rematch and menu buttons, once the battle is over.
var _after: AfterBattle
## The arguments the setup screen started this battle with, used instead of the command line's.
static var launch_args: PackedStringArray = []
## Draws fighters, the camera and projectiles smoothly between video frames in the window;
## null while recording, where every frame is one step.
var _smooth: SmoothMotion


func _ready() -> void:
	UiFonts.use_by_default()
	var args := launch_args if not launch_args.is_empty() else OS.get_cmdline_user_args()
	var handled := Cli.info(args, HELP % [Cli.SPEC_FLAGS_HELP, Cli.INFO_HELP])
	if handled >= 0:
		get_tree().quit(handled)
		return
	var options := parse_args(args)
	if options.has("error"):
		return _fail(options.error)
	var spec: Variant = options.flag_spec if not options.flag_spec.is_empty() \
		else JSON.parse_string(FileAccess.get_file_as_string(options.spec))
	if spec is Dictionary and spec.has("error"):
		return _fail(spec.error)
	if not spec is Dictionary:
		return _fail("cannot read battle spec %s" % options.spec)
	var loaded := BattleData.load_all()
	if loaded.has("error"):
		return _fail(loaded.error)
	var names_problem := Cli.check_spec(spec, loaded.data)
	if not names_problem.is_empty():
		return _fail(names_problem)
	if not options.flag_spec.is_empty():
		Appearance.roll_missing(spec, loaded.data.roster)
	var looks_problem := Appearance.check(spec, loaded.data.roster)
	if not looks_problem.is_empty():
		return _fail(looks_problem)
	var controllers := Controllers.for_spec(spec)
	if controllers.has("error"):
		return _fail(controllers.error)
	var created := Battle.create(spec, loaded.data, controllers.controllers)
	if created.has("error"):
		return _fail(created.error)
	battle = created.battle
	print("\n".join(Cli.describe(spec, battle, not options.flag_spec.is_empty())))
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
	var looks: Array[Dictionary] = []
	for side in 2:
		var entry: Dictionary = loaded.data.roster[battle.fighters[side].species_id]
		var look := Appearance.resolve(entry, spec.fighters[side], MODELS_DIR)
		if not look.warning.is_empty():
			printerr("warning: " + look.warning)
		looks.append(look)
		var view := FighterView.from_model(MODELS_DIR.path_join(look.model), entry.scale, entry.height, skin_path(look))
		if view == null:
			return _fail("cannot load the model %s; run tools/assets.gd" % look.model)
		add_child(view)
		view.set_hovering("Flying" in battle.fighters[side].types or view.floats())
		_views.append(view)
	for side in 2:
		_views[side].watch(_views[1 - side])
	_add_crowd(loaded.data)
	_move_fx = MoveFX.new()
	add_child(_move_fx)
	for fighter in battle.fighters:
		for move in fighter.moves:
			_move_fx.styles[move.id] = MoveStyle.of(move.id, loaded.data.moves[move.id])
	if options.cobblemon_fx:
		var moves: Array = []
		for fighter in battle.fighters:
			moves.append_array(fighter.moves)
		var problem := _move_fx.use_cobblemon(_views, moves)
		if not problem.is_empty():
			printerr("warning: drawing the mesh move styles, since " + problem)
	var portraits := []
	for side in 2:
		var entry: Dictionary = loaded.data.roster[battle.fighters[side].species_id]
		var portrait := FighterPortrait.create(MODELS_DIR.path_join(looks[side].model), entry.scale, entry.height, skin_path(looks[side]))
		if portrait != null:
			add_child(portrait)
		portraits.append(portrait.get_texture() if portrait != null else null)
	_hud = Hud.new()
	_hud.move_effects_credit = _move_fx.cobblemon != null
	add_child(_hud)
	_hud.setup([battle.fighters[0].name, battle.fighters[1].name], size, [battle.fighters[0].types, battle.fighters[1].types], portraits,
		[looks[0].shiny, looks[1].shiny])
	var arena_name: String = Arenas.preset(battle.arena).get("name", battle.arena)
	_sound = BattleSound.new()
	add_child(_sound)
	_sound.setup([spec.fighters[0].species, spec.fighters[1].species])
	_sound.intro()
	_music = BattleMusic.new()
	add_child(_music)
	_music.setup(SimRandom.stream(int(spec.seed), MUSIC_STREAM))
	_music.start()
	_arena_sound = ArenaSound.new()
	add_child(_arena_sound)
	_arena_sound.setup(Arenas.enclosed(battle.arena), str(Arenas.preset(battle.arena).get("field", "")), _crowd.fill)
	_arena_sound.start()
	_views[0].play_role_after("cry", 0)
	_views[1].play_role_after("cry", BattleSound.INTRO_CRY_GAP)
	for side in 2:
		if looks[side].shiny:
			_move_fx.sparkle(_views[side], 0 if side == 0 else BattleSound.INTRO_CRY_GAP)
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
	if not _is_recording():
		_smooth = SmoothMotion.new()
		_move_fx.smooth = _smooth

	if _live:
		var player := battle.fighters[_player_side]
		_hud.show_move_bar(player.moves.map(func(m: BattleMove) -> String: return m.name),
			player.moves.map(func(m: BattleMove) -> String: return m.type), PlayerController.MOVE_KEYS,
			PlayerController.FEINT_KEY, PlayerController.GUARD_KEY)
		_hud.show_hint("Move: WASD / stick   Dodge: Space / A   Guard: G / RT   Feint: hold Shift / LB   F3: AI scores")
		_event_index = 0
		for side in 2:
			_hud.set_hp(side, 1.0, true)
		_hud.set_intro_subtitle(arena_name + _weather_subtitle())
		_arena.weather.snap(battle.conditions.weather)
		_arena.surge.snap(battle.conditions.surge)
		_track_smoothed()
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
	# A clip that skips past the start of overtime never sees its event.
	var overtime := battle.tick >= roundi(Rules.OVERTIME_SECONDS * Rules.TICK_RATE)
	if overtime:
		_music.overtime()
	_hud.set_intro_subtitle(arena_name + _weather_subtitle() + (" · Overtime" if overtime else ""))
	_arena.weather.snap(battle.conditions.weather)
	_arena.surge.snap(battle.conditions.surge)
	while _caption_index < plan.captions.size() and int(plan.captions[_caption_index].tick) < _tick:
		_caption_index += 1
	_begin_tick()
	_sync_views(_shown_tick())
	for side in 2:
		var fighter := battle.fighters[side]
		_hud.set_hp(side, float(fighter.hp) / fighter.max_hp, true)
		# A clip can start mid-battle, after conditions were inflicted.
		_hud.set_status(side, fighter.status, not fighter.status.is_empty())
		_hud.set_status(side, "confusion", fighter.confusion_ticks > 0)
		_views[side].set_asleep(fighter.status == "slp")
	_track_smoothed()


## Hands the fighters and the camera to the smoothing, which projectiles join as they fly.
func _track_smoothed() -> void:
	if _smooth == null:
		return
	for view in _views:
		for node in view.smoothed_nodes():
			_smooth.track(node)
	_smooth.track_camera(_camera)


## Runs a copy of the battle headless and plans its presentation. A knockout's instant replay
## gets another copy, stepped to the replay's first tick.
func _plan(spec: Dictionary, data: BattleData) -> Dictionary:
	var preview: Battle = Battle.create(spec, data, Controllers.for_spec(spec).controllers).battle
	preview.run()
	_preview_events = preview.events
	var move_power := [{}, {}]
	for side in 2:
		for move in preview.fighters[side].moves:
			move_power[side][move.id] = move.power
	var max_hp := [preview.fighters[0].max_hp, preview.fighters[1].max_hp]
	var planned := Director.plan(preview.events, preview.tick, max_hp, move_power,
		battle.random_stream(Battle.Stream.COSMETIC))
	if not planned.replay.is_empty():
		_replay_battle = Battle.create(spec, data, Controllers.for_spec(spec).controllers).battle
		while _replay_battle.tick < int(planned.replay.start):
			_replay_battle.step()
	return planned


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
		if _smooth != null:
			_smooth.restore()
		_next_frame()
		if _smooth != null:
			_smooth.capture()
	if _smooth != null:
		_smooth.show(clampf(_accumulator * Rules.TICK_RATE, 0.0, 1.0))
		_move_fx.shift_riders()


## One video frame: hold the current tick, or advance to the next one. After the plan (or
## the clip window) ends, the credits card shows for Hud.CREDITS_FRAMES before a clip finishes.
func _next_frame() -> void:
	if _live:
		_next_live_frame()
		return
	if _tick >= _end_tick:
		if _credits_frames == 0:
			_hud.show_credits()
			_music.fade_out(Hud.CREDITS_FRAMES)
			_arena_sound.set_level(BattleMusic.SILENT_DB, Hud.CREDITS_FRAMES)
			_fx.visible = false  # callouts stop animating here and draw above the HUD
		if _credits_frames < Hud.CREDITS_FRAMES:
			_credits_frames += 1
			_hud.next_frame()
			_sound.next_frame()
			_next_audio_frame()
		elif _clip_mode:
			_finish()
		elif _after == null:
			_show_after_battle()
		return
	if _replay_due():
		_begin_replay()
	if _replaying and _next_replay_frame():
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
	_advance_effects()
	_fx.set_speed_lines(_segment.get("shot", -1) == Director.Shot.CLOSE_UP)
	_sync_views(_shown_tick())


## Advances every animation, effect and sound by one video frame.
func _advance_effects() -> void:
	for view in _views:
		view.next_frame()
	_crowd.next_frame()
	_fx.next_frame()
	_move_fx.next_frame()
	_hud.next_frame()
	_sync_conditions()
	_sound.next_frame()
	_next_audio_frame()
	if _overlay.visible:
		_overlay.refresh()


## The instant replay starts as the presentation is about to show its planned tick ("at",
## the victory's start), once.
func _replay_due() -> bool:
	return _replay_battle != null and _main_battle == null and _hold_frames == 0 and _tick == int(plan.replay.at)


## Cuts to the instant replay: the replay's copy of the battle stands in for the battle, the
## fighters get back up, the HUD shows the replay tag, and a white flash hides the cut.
func _begin_replay() -> void:
	_main_battle = battle
	_main_event_index = _event_index
	battle = _replay_battle
	_event_index = battle.events.size()
	_replaying = true
	_replay_tick = int(plan.replay.start) - 1
	_replay_hold = 0
	_hold_is_hitstop = false
	_fired_tick = [-1, -1]
	_hit_counts = [0, 0]
	var scale := 1.0 / int(plan.replay.frames_per_tick)
	for side in 2:
		_views[side].rewind()
		_views[side].set_asleep(battle.fighters[side].status == "slp")
		_views[side].set_time_scale(scale)
	_crowd.set_time_scale(scale)
	_hud.show_replay()
	_fx.cut_flash()
	if _smooth != null:
		_smooth.snap_all()


## One video frame of the instant replay: hold the replayed tick, or step the copy to the
## next one. Returns false once the replay is over, after cutting back to the battle, so this
## frame goes on to the victory.
func _next_replay_frame() -> bool:
	var replay: Dictionary = plan.replay
	_segment_frames += 1
	_frames_shown += 1
	if _replay_hold > 0:
		_replay_hold -= 1
	else:
		_replay_tick += 1
		if _replay_tick >= int(replay.end):
			_end_replay()
			return false
		if not battle.is_over():
			_step_battle()
		_replay_hold = int(replay.frames_per_tick) - 1
		var segment := Director.shot_for(replay.shots, _replay_tick)
		if segment != _segment:
			_segment = segment
			_segment_frames = 0
	_advance_effects()
	_fx.set_speed_lines(false)
	_sync_views(_replay_tick)
	return true


func _end_replay() -> void:
	battle = _main_battle
	_event_index = _main_event_index
	_replaying = false
	_hud.hide_replay()
	_fx.cut_flash()
	if _smooth != null:
		_smooth.snap_all()


## Music and the arena's sound run in real time, through hit-stop and slow motion alike.
func _next_audio_frame() -> void:
	_music.next_frame()
	_arena_sound.next_frame(_crowd.excitement)


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
			_save_spec()
			_show_after_battle()
	elif _hold_frames > 0:
		_hold_frames -= 1
		if _hold_frames == 0:
			for view in _views:
				view.set_time_scale(1.0)
			_crowd.set_time_scale(1.0)
	else:
		_step_battle()
	if _live_frames == HINT_FRAMES and not battle.is_over():
		_hud.show_hint("")
	_advance_effects()
	for side in 2:
		var fighter := battle.fighters[side]
		_views[side].place(fighter.position, fighter.facing, _arena.surface_at(fighter.position, fighter.ground))
		_hud.set_hp(side, float(fighter.hp) / fighter.max_hp)
	_hud.update_move_bar(battle.fighters[_player_side])
	_move_fx.sync_projectiles(battle)
	_player_camera.apply(_camera, _views[_player_side], _views[1 - _player_side])
	_update_sight()


## Saves the battle's spec (Battle.saved_spec) so it replays exactly (and tools/record.gd can
## render it).
func _save_spec() -> void:
	var saved := battle.saved_spec()
	var dir := ProjectSettings.globalize_path(SPECS_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	if not FileAccess.file_exists(dir.get_base_dir().path_join(".gdignore")):
		FileAccess.open(dir.get_base_dir().path_join(".gdignore"), FileAccess.WRITE).close()
	var names := "-vs-".join(battle.fighters.map(func(f: Fighter) -> String: return f.species_id))
	var path := dir.path_join("%s_%s_%d.json" % [Time.get_datetime_string_from_system().replace(":", "-"), names, int(battle.spec.seed)])
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(saved, "", false, true))
	file.close()
	print("battle spec saved to %s" % path)


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
	_crowd.set_time_scale(0.0 if hitstop > 0 else 1.0 / slow)
	if not plan.victory.is_empty() and shown >= int(plan.victory.start) and not _victory_shown:
		_show_victory(int(plan.victory.side))
	while _caption_index < plan.captions.size() and int(plan.captions[_caption_index].tick) <= shown:
		var caption: Dictionary = plan.captions[_caption_index]
		_hud.caption(caption.text, int(caption.side))
		_caption_index += 1
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
				_views[event.side].play_role(wind_up_role(move), move.windup_ticks / float(Rules.TICK_RATE))
				_move_fx.windup(_views[event.side], move)
				_hit_counts[event.side] = 0
				_hud.banner(event.side, move.name, move.type)
				_sound.windup(move)
			"feint":
				# Looks like the real wind-up, without the move's banner: the move never comes.
				var move := _move(event.side, event.move)
				_views[event.side].play_role(wind_up_role(move), move.windup_ticks / float(Rules.TICK_RATE))
				_move_fx.windup(_views[event.side], move, int(event.ticks))
				_sound.windup(move)
			"feint_end":
				_views[event.side].break_off()
			"hit":
				var defender := 1 - int(event.side)
				var move := _move(event.side, event.move)
				var share := float(event.damage) / battle.fighters[defender].max_hp
				_hit_counts[event.side] += 1
				var big: bool = event.crit or event.effectiveness > 1.0
				# Big hits get a shocked reaction from species that have one.
				_views[defender].play_role("shock" if big and _views[defender].has_animation("shock") else "recoil")
				_views[defender].take_hit(ImpactFX.IMPACT_SEQUENCE.size() if big else 0)
				_fx.on_hit(event, _views[defender], share, big)
				if _live:
					# Hit-stop in play pauses the battle itself, so it stays fair and replays exactly.
					_hold_frames = Director.HEAVY_HITSTOP_FRAMES if big else Director.HITSTOP_FRAMES
					for view in _views:
						view.set_time_scale(0.0)
					_crowd.set_time_scale(0.0)
				if move.kind == BattleMove.Kind.MELEE:
					_move_fx.melee(_views[event.side], _views[defender], move)
				elif _fired_tick[event.side] == int(event.tick):
					_move_fx.point_blank(_views[event.side], _views[defender], move)
				_move_fx.hit(_views[defender], move, big)
				_sound.hit(move, big)
				if big:
					_hud.shake(defender)
				if big or share >= CHEER_SHARE:
					_crowd.cheer(0.4 + share * 1.5 + (0.25 if big else 0.0))
					_arena_sound.cheer()
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
				_move_fx.aura(_views[event.side], HEAL_COLOUR, true, true)
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
			"ability":
				_fx.announce(_views[event.side], str(event.name), ABILITY_CALLOUT, 52)
			"item":
				_fx.announce(_views[event.side], str(event.name), ITEM_CALLOUT, 52)
			"ability_damage", "item_damage":
				_views[event.side].take_hit()
				_fx.announce(_views[event.side], "-%d" % event.damage, Color(1, 1, 1), 44)
			"weather":
				# A battle's starting weather shows on the intro card and the HUD instead, and a
				# renewed one only refills the HUD's timer.
				if not _replaying and int(event.tick) > 0 and not event.get("renewed", false):
					_hud.flash_title(WEATHER_STARTS[event.weather], WEATHER_COLOURS[event.weather])
			"weather_end":
				if not _replaying:
					_hud.flash_title(WEATHER_ENDS[event.weather], WEATHER_COLOURS[event.weather])
			"surge":
				if not _replaying and int(event.tick) > 0 and not event.get("renewed", false):
					_hud.flash_title(SURGE_STARTS[event.surge], ArenaSurge.COLOURS[event.surge])
			"surge_end":
				if not _replaying:
					_hud.flash_title(SURGE_ENDS[event.surge], ArenaSurge.COLOURS[event.surge])
			"screen_end":
				if event.get("shattered", false):
					_fx.announce(_views[event.side], "Shattered!", ScreenPanes.COLOURS[event.screen], 56)
			"weather_damage":
				_fx.announce(_views[event.side], "-%d" % event.damage, WEATHER_COLOURS[event.weather], 44)
			"stunned":
				_fx.announce(_views[event.side], "Can't move!", Hud.STATUS_BADGES.par[1].lightened(0.3), 48)
			"dodge":
				_move_fx.dodge(_views[event.side], Vector2(event.direction[0], event.direction[1]))
			"guard":
				_move_fx.guard(_views[event.side])
			"guarded":
				_move_fx.guard(_views[event.side], true)
				_fx.announce(_views[event.side], "Parried!" if event.parry else "Blocked!", GUARD_CALLOUT, 60)
				if event.parry:
					_views[1 - int(event.side)].play_role("recoil")
			"dodged":
				_fx.on_dodge(_views[event.side])
			"knockout":
				_views[event.side].play_role("faint")
				_views[1 - int(event.side)].celebrate()
				_sound.knockout(event.side)
				_arena_sound.cheer()
				if _replaying:
					# The music is already cut, and the crowd has seen this once.
					_crowd.cheer(REPLAY_CHEER)
					continue
				_crowd.cheer(1.0, KNOCKOUT_CHEER_FRAMES)
				_arena_sound.roar()
				_music.knockout()
				if _live:
					_hud.show_winner("%s wins!" % battle.fighters[1 - int(event.side)].name)
					_music.victory(BattleMusic.CUT_FRAMES)
					_arena_sound.set_level(ArenaSound.STING_DUCK_DB, ArenaSound.DUCK_FRAMES)
			"overtime":
				if _replaying:
					continue
				_hud.flash_title("Overtime!", Color(1.0, 0.55, 0.3))
				_music.overtime()
			"time_up":
				_hud.show_winner("Time up: draw")
				_music.draw()
				for view in _views:
					view.play_role("sad")


## The weather and surge shown last frame, their ticks left then, and the ticks they lasted in
## all (for the HUD's timers).
## Screen panes in front of shielded fighters, and the screens each side's plate shows.
var _screen_panes: ScreenPanes
var _screen_badges := [{}, {}]
var _weather_seen := ""
var _weather_left := 0
var _weather_total := 1.0
var _surge_seen := ""
var _surge_left := 0
var _surge_total := 1.0


## Keeps the weather's and surge's looks and the HUD's condition pills in step with the battle
## shown (the instant replay's copy included), one video frame at a time.
func _sync_conditions() -> void:
	var conditions := battle.conditions
	_arena.weather.show_weather(conditions.weather)
	_arena.weather.next_frame()
	_arena.surge.show_surge(conditions.surge)
	_arena.surge.next_frame()
	if _screen_panes == null:
		_screen_panes = ScreenPanes.new()
		add_child(_screen_panes)
	_screen_panes.sync(conditions.screens, _views, [battle.fighters[0].radius, battle.fighters[1].radius])
	for side in 2:
		for screen: String in ArenaConditions.SCREENS:
			var up: bool = conditions.screens[side].has(screen)
			if up != _screen_badges[side].has(screen):
				_hud.set_status(side, screen, up)
				if up:
					_screen_badges[side][screen] = true
				else:
					_screen_badges[side].erase(screen)
	var entries := []
	if not conditions.weather.is_empty():
		# A new weather (or a renewed one) sets the timer's full length.
		if conditions.weather != _weather_seen or conditions.weather_ticks > _weather_left:
			_weather_total = maxf(_condition_full("weather"), 1.0)
		var left := -1.0 if conditions.weather_ticks < 0 else conditions.weather_ticks / _weather_total
		entries.append({"key": "weather", "text": WEATHER_PILLS[conditions.weather],
			"colour": WEATHER_COLOURS[conditions.weather], "left": left})
	_weather_seen = conditions.weather
	_weather_left = conditions.weather_ticks
	if not conditions.surge.is_empty():
		if conditions.surge != _surge_seen or conditions.surge_ticks > _surge_left:
			_surge_total = maxf(_condition_full("surge"), 1.0)
		entries.append({"key": "surge", "text": conditions.surge,
			"colour": ArenaSurge.COLOURS[conditions.surge], "left": conditions.surge_ticks / _surge_total})
	_surge_seen = conditions.surge
	_surge_left = conditions.surge_ticks
	_hud.set_conditions(entries)


## Ticks the shown weather or surge (`type`, its event's type) lasted when set, for the pill's
## timer.
func _condition_full(type: String) -> float:
	for i in range(battle.events.size() - 1, -1, -1):
		var event: Dictionary = battle.events[i]
		if event.type == type:
			return float(event.seconds) * Rules.TICK_RATE
	return Rules.WEATHER_SECONDS * Rules.TICK_RATE


## " · Rain" for a battle that starts in a weather lasting the battle (from its arena or spec).
func _weather_subtitle() -> String:
	var weather := str(battle.spec.get("weather", Arenas.preset(battle.arena).get("weather", "")))
	return " · " + ArenaConditions.display_name(weather) if not weather.is_empty() else ""


## The planned ending's victory: the HUD's card with the winner's name, HP left and the
## battle's length, the victory sting, and the crowd cheering again.
func _show_victory(side: int) -> void:
	_victory_shown = true
	var winner := battle.fighters[side]
	_hud.show_victory(side, winner.name, float(winner.hp) / winner.max_hp, battle.tick / float(Rules.TICK_RATE))
	_crowd.cheer(1.0, KNOCKOUT_CHEER_FRAMES)
	_arena_sound.cheer()
	_arena_sound.roar()
	_arena_sound.set_level(ArenaSound.STING_DUCK_DB, ArenaSound.DUCK_FRAMES)
	_music.victory()


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


## The animation a move plays on wind-up: damaging moves by category (area moves can be either),
## everything else the status animation.
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


## Places the fighters, HUD and camera for the tick `shown`.
func _sync_views(shown: int) -> void:
	if _hold_is_hitstop and _hold_frames < plan.slow[shown]:
		_hold_is_hitstop = false
		for view in _views:
			view.set_time_scale(1.0 / plan.slow[shown])
		_crowd.set_time_scale(1.0 / plan.slow[shown])
	for side in 2:
		var fighter := battle.fighters[side]
		_views[side].place(fighter.position, fighter.facing, _arena.surface_at(fighter.position, fighter.ground))
		_hud.set_hp(side, float(fighter.hp) / fighter.max_hp)
	_update_sight()
	_move_fx.sync_projectiles(battle)
	var span := maxi(1, int(_segment.end) - int(_segment.start))
	var progress := float(shown - int(_segment.start)) / span
	_rig.apply(_camera, _segment, battle, _segment_frames / float(Rules.TICK_RATE), progress,
		_frames_shown / float(Rules.TICK_RATE), _segment_frames == 0)
	if _rig.cut and _smooth != null:
		_smooth.snap(_camera)


## The arena (its own sky, sun and particles) and the camera.
func _build_stage(arena_name: String) -> void:
	_arena = Arena.create(arena_name, int(battle.spec.seed), [battle.fighters[0].name, battle.fighters[1].name], battle.terrain)
	add_child(_arena)
	_camera = Camera3D.new()
	_camera.far = Terrain.WORLD_RADIUS * 3.0
	add_child(_camera)


## Spectators, if the arena has stands: figures in a share of the seats, and watchers that
## suit the arena in the front row, watching the fighters (half each), as many as its preset says.
func _add_crowd(data: BattleData) -> void:
	_crowd = Crowd.create(_arena, int(battle.spec.seed), Arenas.preset(battle.arena).get("crowd", {}))
	add_child(_crowd)
	var seats := _crowd.watcher_seats(_crowd.watcher_count)
	if not seats.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%d|%d" % [int(battle.spec.seed), WATCHER_STREAM])
		var fighters := battle.fighters.map(func(f: Fighter) -> String: return f.species_id)
		var ids := Crowd.choose_watchers(Arenas.preset(battle.arena).get("suits", []), data.roster, data.species, fighters, rng, seats.size())
		for i in ids.size():
			var entry: Dictionary = data.roster[ids[i]]
			var view := FighterView.from_model(MODELS_DIR.path_join(entry.model), entry.scale, entry.height)
			if view == null:
				push_warning("cannot load the model %s for a spectator" % entry.model)
				continue
			_crowd.add_watcher(view, seats[i], _views[i % 2])
			view.set_hovering("Flying" in data.species[ids[i]].get("types", []) or view.floats())
	_crowd.build()


## The path of a look's shiny skin (Appearance.resolve()), or "" for none.
static func skin_path(look: Dictionary) -> String:
	return MODELS_DIR.path_join(look.skin) if not look.skin.is_empty() else ""


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
			if _after != null:
				get_tree().reload_current_scene()
		KEY_ESCAPE:
			if not _clip_mode:
				get_tree().change_scene_to_file(SetupScreen.SCENE)


func _show_after_battle() -> void:
	_after = AfterBattle.new()
	_after.rematch.connect(get_tree().reload_current_scene)
	_after.menu.connect(get_tree().change_scene_to_file.bind(SetupScreen.SCENE))
	add_child(_after)


func _is_recording() -> bool:
	return not Array(OS.get_cmdline_args()).filter(func(a: String) -> bool: return a.begins_with("--write-movie")).is_empty()


## The view's options from its user arguments (see the top of this file), with "error" for an
## unknown option.
static func parse_args(args: PackedStringArray) -> Dictionary:
	var parsed := SpecFlags.parse(args)
	var options := {"spec": DEFAULT_SPEC, "clip_seconds": 0.0, "expect_checksum": "", "ai_debug": false,
		"cobblemon_fx": true, "flag_spec": SpecFlags.to_spec(parsed.flags)}
	var unknown := Cli.unknown_option(parsed.rest, OPTIONS)
	if not unknown.is_empty():
		options.error = unknown
	for arg: String in parsed.rest:
		if arg == "--ai-debug":
			options.ai_debug = true
		elif arg == "--mesh-fx":
			options.cobblemon_fx = false
		elif arg == "--cobblemon-fx":
			pass  # the default now; still accepted so older commands keep working
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
