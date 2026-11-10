class_name ImpactFX
extends CanvasLayer
## Screen-space hit feedback (concepts_brief.md §12.4): impact frames, screen shake, speed
## lines and callouts. Everything counts video frames rather than real time, so recorded
## clips are identical on every render and effects line up with hit-stop.

## Impact frames on criticals and super-effective hits: a white flash, then a two-tone frame.
const FLASH_ALPHA := 0.75
const IMPACT_SEQUENCE: Array[String] = ["flash", "ink"]
## Callouts stay this far (in reference pixels) inside the screen edges.
const SCREEN_MARGIN := 40.0
## Largest vertical offset a callout uses (a critical and super-effective hit stack three).
const MAX_STACK_OFFSET := 140.0
## Shake: offset in metres at full strength, frames it lasts, and strength per HP share dealt.
const SHAKE_MAX := 0.35
const SHAKE_FRAMES := 14
const SHAKE_PER_SHARE := 2.5
## Callouts rise this far (in reference pixels) over their lifetime.
const CALLOUT_FRAMES := 40
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
var _impact_queue: Array[String] = []
var _shake_frames := 0
var _shake_strength := 0.0
var _frame := 0
var _callouts: Array[Dictionary] = []


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
	var anchor := defender.global_position + Vector3.UP * defender.height * 0.9
	_callout("-%d" % event.damage, anchor, Color(1, 1, 1), 64, 0.0)
	if event.crit:
		_callout("Critical hit!", anchor, Color(1.0, 0.85, 0.2), 72, 70.0)
	if event.effectiveness > 1.0:
		_callout("It's super effective!", anchor, Color(1.0, 0.45, 0.25), 72, 140.0 if event.crit else 70.0)
	elif event.effectiveness < 1.0:
		_callout("Not very effective...", anchor, Color(0.75, 0.8, 0.9), 56, 70.0)


func on_dodge(dodger: FighterView) -> void:
	_callout("Dodged!", dodger.global_position + Vector3.UP * dodger.height * 0.9, Color(0.6, 0.9, 1.0), 60, 0.0)


## Speed lines fade in while `active` (strong wind-ups in close-up) and out otherwise.
func set_speed_lines(active: bool) -> void:
	var current: float = _speed_lines.material.get_shader_parameter("intensity")
	_speed_lines.material.set_shader_parameter("intensity", move_toward(current, 1.0 if active else 0.0, 0.2))


## Advances every effect by one video frame.
func next_frame() -> void:
	_frame += 1
	_speed_lines.material.set_shader_parameter("seed", float(_frame / 3))
	var step: String = _impact_queue.pop_front() if not _impact_queue.is_empty() else ""
	_flash.color.a = FLASH_ALPHA if step == "flash" else 0.0
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
		var t: float = callout.age / float(CALLOUT_FRAMES)
		var label: Label = callout.label
		var screen := _camera.unproject_position(callout.anchor) if not _camera.is_position_behind(callout.anchor) else label.position
		var wanted := screen - label.size * 0.5 + Vector2(0, -callout.offset - CALLOUT_RISE * t) * _ui_scale
		var margin := SCREEN_MARGIN * _ui_scale
		# Clamping keeps the stack order: callouts with a smaller offset sit further down.
		var stack: float = (MAX_STACK_OFFSET - callout.offset) * _ui_scale
		label.position = wanted.clamp(Vector2(margin, _hud_bands.x + margin + stack),
			_screen - label.size - Vector2(margin, _hud_bands.y + margin))
		var pop := 1.0 + 0.4 * maxf(0.0, 1.0 - t * 6.0)
		label.scale = Vector2.ONE * pop
		label.modulate.a = clampf((1.0 - t) * 3.0, 0.0, 1.0)
		if callout.age >= CALLOUT_FRAMES:
			label.queue_free()
			_callouts.erase(callout)


func _callout(text: String, anchor: Vector3, colour: Color, font_size: int, offset: float) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", roundi(font_size * _ui_scale))
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", roundi(14 * _ui_scale))
	add_child(label)
	label.size = label.get_minimum_size()
	label.pivot_offset = label.size * 0.5
	_callouts.append({"label": label, "anchor": anchor, "age": 0, "offset": offset})


func _full_screen(size: Vector2) -> ColorRect:
	var rect := ColorRect.new()
	rect.size = size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	return rect
