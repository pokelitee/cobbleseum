class_name ImpactFX
extends CanvasLayer
## Screen-space hit feedback (concepts_brief.md §12.4): impact frames, screen shake, speed
## lines and callouts. Everything counts video frames rather than real time, so recorded
## clips are identical on every render and effects line up with hit-stop.

## Impact frames on criticals and super-effective hits: a white flash, then a two-tone frame.
const FLASH_ALPHA := 0.75
const IMPACT_SEQUENCE: Array[String] = ["flash", "ink"]
## Callouts stay this far (in reference pixels) inside the screen edges, and this far apart
## when they stack over one fighter.
const SCREEN_MARGIN := 40.0
const STACK_GAP := 6.0
## Callouts sit over this share of their fighter's height, following it as it moves.
const CALLOUT_HEIGHT := 0.9
## Shake: offset in metres at full strength, frames it lasts, and strength per HP share dealt.
const SHAKE_MAX := 0.35
const SHAKE_FRAMES := 14
const SHAKE_PER_SHARE := 2.5
## Callouts rise this far (in reference pixels) over their lifetime.
const CALLOUT_FRAMES := 40
## A white flash that covers a cut (into and out of the instant replay), fading over this many frames.
const CUT_FLASH_FRAMES := 8
const CALLOUT_RISE := 90.0
const REFERENCE_SIZE := 1080.0
const IMPACT_SHADER := preload("res://game/presentation/shaders/impact_frame.gdshader")
const SPEED_LINES_SHADER := preload("res://game/presentation/shaders/speed_lines.gdshader")

var _camera: Camera3D
var _ui_scale := 1.0
var _screen := Vector2.ZERO
## Screen bands the HUD occupies (top, bottom) in pixels; callouts stay out of them.
var _hud_bands := Vector2.ZERO
var _flash: ColorRect
var _impact: ColorRect
var _speed_lines: ColorRect
## Kept here: a shader parameter never set reads back as null, not the shader's default.
var _speed_line_intensity := 0.0
var _impact_queue: Array[String] = []
var _shake_frames := 0
var _shake_strength := 0.0
var _frame := 0
var _callouts: Array[Dictionary] = []
## Counts callouts as they're made, so ones made on the same frame keep their order.
var _callout_count := 0
var _cut_flash := 0


func setup(camera: Camera3D, viewport_size: Vector2, hud_bands: Vector2) -> void:
	_camera = camera
	_screen = viewport_size
	_hud_bands = hud_bands
	_ui_scale = minf(viewport_size.x, viewport_size.y) / REFERENCE_SIZE
	_speed_lines = _full_screen(viewport_size)
	_speed_lines.material = ShaderMaterial.new()
	_speed_lines.material.shader = SPEED_LINES_SHADER
	_speed_lines.material.set_shader_parameter("aspect", viewport_size.x / viewport_size.y)
	_impact = _full_screen(viewport_size)
	_impact.material = ShaderMaterial.new()
	_impact.material.shader = IMPACT_SHADER
	_impact.visible = false
	_flash = _full_screen(viewport_size)
	_flash.color = Color(1, 1, 1, 0)


## Reacts to a "hit" event. `big` hits (criticals, super-effective) get impact frames.
func on_hit(event: Dictionary, defender: FighterView, damage_share: float, big: bool) -> void:
	_shake_frames = SHAKE_FRAMES
	_shake_strength = minf(SHAKE_MAX, damage_share * SHAKE_PER_SHARE * SHAKE_MAX + (0.1 if big else 0.0))
	if big:
		_impact_queue = IMPACT_SEQUENCE.duplicate()
	_callout("-%d" % event.damage, defender, Color(1, 1, 1), 64)
	if event.crit:
		_callout("Critical hit!", defender, Color(1.0, 0.85, 0.2), 72)
	if event.effectiveness > 1.0:
		_callout("It's super effective!", defender, Color(1.0, 0.45, 0.25), 72)
	elif event.effectiveness < 1.0:
		_callout("Not very effective...", defender, Color(0.75, 0.8, 0.9), 56)


## A callout above a fighter, e.g. "Attack rose!" or "Burned!".
func announce(view: FighterView, text: String, colour: Color, font_size := 56) -> void:
	_callout(text, view, colour, font_size)


func on_dodge(dodger: FighterView) -> void:
	_callout("Dodged!", dodger, Color(0.6, 0.9, 1.0), 60)


## Whites out the screen and fades back over CUT_FLASH_FRAMES, hiding a cut. Callouts from
## before the cut go, since they belong to the other side of it.
func cut_flash() -> void:
	_cut_flash = CUT_FLASH_FRAMES
	for callout in _callouts:
		callout.label.queue_free()
	_callouts.clear()


## Speed lines fade in while `active` (strong wind-ups in close-up) and out otherwise.
func set_speed_lines(active: bool) -> void:
	_speed_line_intensity = move_toward(_speed_line_intensity, 1.0 if active else 0.0, 0.2)
	_speed_lines.material.set_shader_parameter("intensity", _speed_line_intensity)


## Advances every effect by one video frame.
func next_frame() -> void:
	_frame += 1
	_speed_lines.material.set_shader_parameter("seed", float(_frame / 3))
	var step: String = _impact_queue.pop_front() if not _impact_queue.is_empty() else ""
	_flash.color.a = FLASH_ALPHA if step == "flash" else 0.0
	if _cut_flash > 0:
		_flash.color.a = maxf(_flash.color.a, float(_cut_flash) / CUT_FLASH_FRAMES)
		_cut_flash -= 1
	_impact.visible = step == "ink"
	if _shake_frames > 0:
		_shake_frames -= 1
		var strength := _shake_strength * _shake_frames / float(SHAKE_FRAMES)
		# Deterministic jitter: fixed, unrelated frequencies per axis.
		_camera.h_offset = sin(_frame * 2.71) * strength
		_camera.v_offset = sin(_frame * 3.97 + 1.3) * strength
	else:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
	for callout in _callouts.duplicate():
		callout.age += 1
		if callout.age >= CALLOUT_FRAMES:
			(callout.label as Label).queue_free()
			_callouts.erase(callout)
	place_callouts()


## Places each callout over its fighter as the camera now sees it, `between` (0 to 1) of a
## video frame on from the last one: in the window this runs every display frame, so callouts
## follow their fighters smoothly. Callouts over one fighter stack, the newest at the bottom
## (those made together in the order they were made), rising as they age and pushing older ones
## up rather than overlapping them; the stack stays on screen and out of the HUD's bands.
func place_callouts(between := 0.0) -> void:
	var stacks := {}
	for callout in _callouts:
		stacks.get_or_add(callout.view, []).append(callout)
	var margin := SCREEN_MARGIN * _ui_scale
	var top := _hud_bands.x + margin
	var bottom := _screen.y - _hud_bands.y - margin
	for view: Variant in stacks:
		var stack: Array = stacks[view]
		stack.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a.age < b.age if a.age != b.age else a.order < b.order)
		if is_instance_valid(view):
			var fighter := view as FighterView
			var anchor := fighter.global_position + Vector3.UP * fighter.height * CALLOUT_HEIGHT
			if not _camera.is_position_behind(anchor):
				stack[0].screen = _camera.unproject_position(anchor)
		var screen: Vector2 = stack[0].get("screen", _screen * 0.5)
		var above := INF
		for callout: Dictionary in stack:
			callout.screen = screen
			var label: Label = callout.label
			var t := clampf((callout.age + between) / float(CALLOUT_FRAMES), 0.0, 1.0)
			var y := screen.y - label.size.y * 0.5 - CALLOUT_RISE * t * _ui_scale
			y = minf(y, above - label.size.y - STACK_GAP * _ui_scale)
			above = y
			label.position = Vector2(clampf(screen.x - label.size.x * 0.5, margin, _screen.x - label.size.x - margin), y)
			label.scale = Vector2.ONE * (1.0 + 0.4 * maxf(0.0, 1.0 - t * 6.0))
			label.modulate.a = clampf((1.0 - t) * 3.0, 0.0, 1.0)
		var highest: float = (stack[-1].label as Label).position.y
		var lowest: float = (stack[0].label as Label).position.y + (stack[0].label as Label).size.y
		# Kept below the HUD's top band first: a stack too tall for the screen runs off the bottom.
		var shift := minf(0.0, bottom - lowest)
		shift = maxf(shift, top - highest)
		for callout: Dictionary in stack:
			(callout.label as Label).position.y += shift


func _callout(text: String, view: FighterView, colour: Color, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiFonts.DISPLAY)
	label.add_theme_font_size_override("font_size", roundi(font_size * _ui_scale))
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", roundi(14 * _ui_scale))
	add_child(label)
	label.size = label.get_minimum_size()
	label.pivot_offset = label.size * 0.5
	_callouts.append({"label": label, "view": view, "age": 0, "order": _callout_count})
	_callout_count += 1


func _full_screen(size: Vector2) -> ColorRect:
	var rect := ColorRect.new()
	rect.size = size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	return rect
