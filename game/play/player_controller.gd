class_name PlayerController
extends RefCounted
## Turns keyboard and gamepad input into the same intents the AI produces
## (concepts_brief.md §9.1): a movement direction, a dodge, or a move 1-4.
## Keyboard: WASD or arrows to move, Space to dodge, J K L I (or 1-4) for moves.
## Gamepad: left stick to move, A to dodge, X Y B RB for moves.
## Movement is relative to the camera. Button presses are latched between frames and ticks
## (poll() runs every frame, decide() every tick), so no tap is lost.

const MOVE_ACTIONS: Array[String] = ["cobbleseum_move_1", "cobbleseum_move_2", "cobbleseum_move_3", "cobbleseum_move_4"]
const DODGE_ACTION := "cobbleseum_dodge"
const DIRECTION_ACTIONS: Array[String] = ["cobbleseum_left", "cobbleseum_right", "cobbleseum_forward", "cobbleseum_back"]
## Labels shown in the move bar, in move order.
const MOVE_KEYS: Array[String] = ["J / X", "K / Y", "L / B", "I / RB"]
## Stick input is rounded to this step so saved battle specs store short, exact numbers.
const INPUT_STEP := 0.01

## Camera-relative input, latched until the next decide().
var stick := Vector2.ZERO
var pending_use := -1
var pending_dodge := false
## The camera's forward direction on the floor (sim x, z), for camera-relative movement.
var camera_forward := Vector2(0, 1)


## Registers the input actions this controller reads, once per run.
static func ensure_input_actions() -> void:
	if InputMap.has_action(DODGE_ACTION):
		return
	var keys := {
		"cobbleseum_left": [KEY_A, KEY_LEFT], "cobbleseum_right": [KEY_D, KEY_RIGHT],
		"cobbleseum_forward": [KEY_W, KEY_UP], "cobbleseum_back": [KEY_S, KEY_DOWN],
		DODGE_ACTION: [KEY_SPACE],
		"cobbleseum_move_1": [KEY_J, KEY_1], "cobbleseum_move_2": [KEY_K, KEY_2],
		"cobbleseum_move_3": [KEY_L, KEY_3], "cobbleseum_move_4": [KEY_I, KEY_4],
	}
	var buttons := {DODGE_ACTION: JOY_BUTTON_A, "cobbleseum_move_1": JOY_BUTTON_X, "cobbleseum_move_2": JOY_BUTTON_Y,
		"cobbleseum_move_3": JOY_BUTTON_B, "cobbleseum_move_4": JOY_BUTTON_RIGHT_SHOULDER}
	var axes := {"cobbleseum_left": [JOY_AXIS_LEFT_X, -1.0], "cobbleseum_right": [JOY_AXIS_LEFT_X, 1.0],
		"cobbleseum_forward": [JOY_AXIS_LEFT_Y, -1.0], "cobbleseum_back": [JOY_AXIS_LEFT_Y, 1.0]}
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
	for i in MOVE_ACTIONS.size():
		if Input.is_action_just_pressed(MOVE_ACTIONS[i]):
			pending_use = i


func decide(battle: Battle, side: int) -> Dictionary:
	var direction := to_world(stick)
	var intent := {"move": direction}
	if pending_dodge:
		var me := battle.fighters[side]
		var away := me.position - battle.fighters[1 - side].position
		# Dodge where the stick points, or sideways from the foe when it's centred.
		intent.dodge = direction if direction.length_squared() > 0.01 else Vector2(-away.y, away.x).normalized()
	if pending_use >= 0:
		intent.use = pending_use
	pending_dodge = false
	pending_use = -1
	return intent


## Stick input (x right, y forward) to a floor direction relative to the camera, rounded.
func to_world(input: Vector2) -> Vector2:
	var forward := camera_forward.normalized() if camera_forward.length_squared() > 0.0 else Vector2(0, 1)
	var right := Vector2(-forward.y, forward.x)
	var world := right * input.x + forward * input.y
	return (world / INPUT_STEP).round() * INPUT_STEP
