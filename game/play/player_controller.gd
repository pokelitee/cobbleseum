class_name PlayerController
extends RefCounted
## Turns keyboard and gamepad input into the same intents the AI produces
## (concepts_brief.md §9.1): a movement direction, a dodge, a guard, a move 1-4, or a feint of one.
## Keyboard: WASD or arrows to move, Space to dodge, J K L I (or 1-4) for moves, held Shift
## to feint the move instead, G to guard.
## Gamepad: left stick to move, A to dodge, X Y B RB for moves, held LB to feint, RT to guard.
## Team battles: Q (D-pad left and right) cycles the highlighted bench member, E (D-pad up)
## switches to it; while the fighter is down after a knockout, the highlighted one is the pick.
## Doubles: T (the right stick's click) locks onto the other foe.
## Movement is relative to the camera. Button presses are latched between frames and ticks
## (poll() runs every frame, decide() every tick), so no tap is lost.

const MOVE_ACTIONS: Array[String] = ["cobbleseum_move_1", "cobbleseum_move_2", "cobbleseum_move_3", "cobbleseum_move_4"]
const DODGE_ACTION := "cobbleseum_dodge"
const FEINT_ACTION := "cobbleseum_feint"
const GUARD_ACTION := "cobbleseum_guard"
## Switching in team battles: cycle the highlighted bench member, then switch to it. After a
## knockout the highlighted one is the pick sent out.
const SWITCH_NEXT_ACTION := "cobbleseum_switch_next"
const SWITCH_PREVIOUS_ACTION := "cobbleseum_switch_previous"
const SWITCH_ACTION := "cobbleseum_switch"
const CYCLE_KEY := "Q / D-pad"
const SWITCH_KEY := "E / D-pad up"
## Doubles: lock onto the other foe.
const TARGET_ACTION := "cobbleseum_target"
const TARGET_KEY := "T / R3"
const DIRECTION_ACTIONS: Array[String] = ["cobbleseum_left", "cobbleseum_right", "cobbleseum_forward", "cobbleseum_back"]
## Labels shown in the move bar, in move order, and for the feint modifier and the guard.
const MOVE_KEYS: Array[String] = ["J / X", "K / Y", "L / B", "I / RB"]
const FEINT_KEY := "Shift / LB"
const GUARD_KEY := "G / RT"
## Stick input is rounded to this step so saved battle specs store short, exact numbers.
const INPUT_STEP := 0.01

## Camera-relative input, latched until the next decide().
var stick := Vector2.ZERO
var pending_use := -1
var pending_feint := -1
var pending_dodge := false
var pending_guard := false
var pending_cycle := 0
var pending_switch := false
var pending_target := false
## The highlighted bench member's team slot (-1 for none), kept in step by decide().
var bench_choice := -1
## The camera's forward direction on the floor (sim x, z), for camera-relative movement.
var camera_forward := Vector2(0, 1)


## Registers the input actions this controller reads, once per run.
static func ensure_input_actions() -> void:
	if InputMap.has_action(DODGE_ACTION):
		return
	var keys := {
		"cobbleseum_left": [KEY_A, KEY_LEFT], "cobbleseum_right": [KEY_D, KEY_RIGHT],
		"cobbleseum_forward": [KEY_W, KEY_UP], "cobbleseum_back": [KEY_S, KEY_DOWN],
		DODGE_ACTION: [KEY_SPACE], FEINT_ACTION: [KEY_SHIFT], GUARD_ACTION: [KEY_G],
		SWITCH_NEXT_ACTION: [KEY_Q], SWITCH_PREVIOUS_ACTION: [], SWITCH_ACTION: [KEY_E], TARGET_ACTION: [KEY_T],
		"cobbleseum_move_1": [KEY_J, KEY_1], "cobbleseum_move_2": [KEY_K, KEY_2],
		"cobbleseum_move_3": [KEY_L, KEY_3], "cobbleseum_move_4": [KEY_I, KEY_4],
	}
	var buttons := {DODGE_ACTION: JOY_BUTTON_A, FEINT_ACTION: JOY_BUTTON_LEFT_SHOULDER, "cobbleseum_move_1": JOY_BUTTON_X, "cobbleseum_move_2": JOY_BUTTON_Y,
		"cobbleseum_move_3": JOY_BUTTON_B, "cobbleseum_move_4": JOY_BUTTON_RIGHT_SHOULDER,
		SWITCH_NEXT_ACTION: JOY_BUTTON_DPAD_RIGHT, SWITCH_PREVIOUS_ACTION: JOY_BUTTON_DPAD_LEFT, SWITCH_ACTION: JOY_BUTTON_DPAD_UP,
		TARGET_ACTION: JOY_BUTTON_RIGHT_STICK}
	var axes := {"cobbleseum_left": [JOY_AXIS_LEFT_X, -1.0], "cobbleseum_right": [JOY_AXIS_LEFT_X, 1.0],
		"cobbleseum_forward": [JOY_AXIS_LEFT_Y, -1.0], "cobbleseum_back": [JOY_AXIS_LEFT_Y, 1.0],
		GUARD_ACTION: [JOY_AXIS_TRIGGER_RIGHT, 1.0]}
	for action: String in keys:
		InputMap.add_action(action, 0.2)
		for key: Key in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
		if buttons.has(action):
			var button := InputEventJoypadButton.new()
			button.button_index = buttons[action]
			InputMap.action_add_event(action, button)
		if axes.has(action):
			var motion := InputEventJoypadMotion.new()
			motion.axis = axes[action][0]
			motion.axis_value = axes[action][1]
			InputMap.action_add_event(action, motion)


## Reads the current input. Called every frame.
func poll() -> void:
	stick = Input.get_vector("cobbleseum_left", "cobbleseum_right", "cobbleseum_back", "cobbleseum_forward")
	if Input.is_action_just_pressed(DODGE_ACTION):
		pending_dodge = true
	if Input.is_action_just_pressed(GUARD_ACTION):
		pending_guard = true
	if Input.is_action_just_pressed(SWITCH_NEXT_ACTION):
		pending_cycle += 1
	if Input.is_action_just_pressed(SWITCH_PREVIOUS_ACTION):
		pending_cycle -= 1
	if Input.is_action_just_pressed(SWITCH_ACTION):
		pending_switch = true
	if Input.is_action_just_pressed(TARGET_ACTION):
		pending_target = true
	for i in MOVE_ACTIONS.size():
		if Input.is_action_just_pressed(MOVE_ACTIONS[i]):
			if Input.is_action_pressed(FEINT_ACTION):
				pending_feint = i
			else:
				pending_use = i


## `index` is the player's fighter's in Battle.fighters (its side, in singles).
func decide(battle: Battle, index: int) -> Dictionary:
	var side := index % 2
	var direction := to_world(stick)
	var intent := {"move": direction}
	if pending_dodge:
		var me := battle.fighters[index]
		var away := me.position - battle.target_of(me).position
		# Dodge where the stick points, or sideways from the foe when it's centred.
		intent.dodge = direction if direction.length_squared() > 0.01 else Vector2(-away.y, away.x).normalized()
	if pending_guard:
		intent.guard = true
	if pending_target and battle.doubles:
		intent.target = 1 - battle.fighters[index].target_place
	if pending_use >= 0:
		intent.use = pending_use
	if pending_feint >= 0:
		intent.feint = pending_feint
	var bench := bench_slots(battle, side)
	if not bench_choice in bench:
		bench_choice = bench[0] if not bench.is_empty() else -1
	if pending_cycle != 0 and not bench.is_empty():
		bench_choice = bench[posmod(bench.find(bench_choice) + pending_cycle, bench.size())]
	if bench_choice >= 0 and (pending_switch or battle.fighters[index].is_knocked_out()):
		intent.switch = bench_choice
	pending_dodge = false
	pending_guard = false
	pending_use = -1
	pending_feint = -1
	pending_cycle = 0
	pending_switch = false
	pending_target = false
	return intent


## The team slots of `side`'s healthy members on the bench, in team order.
static func bench_slots(battle: Battle, side: int) -> Array[int]:
	var slots: Array[int] = []
	for fighter: Fighter in battle.healthy(side):
		if not battle.fighters.has(fighter):
			slots.append(fighter.slot)
	return slots


## Stick input (x right, y forward) to a floor direction relative to the camera, rounded.
func to_world(input: Vector2) -> Vector2:
	var forward := camera_forward.normalized() if camera_forward.length_squared() > 0.0 else Vector2(0, 1)
	var right := Vector2(-forward.y, forward.x)
	var world := right * input.x + forward * input.y
	return (world / INPUT_STEP).round() * INPUT_STEP
