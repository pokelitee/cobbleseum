class_name AfterBattle
extends CanvasLayer
## The choices after a battle in the window: a rematch (R) or back to the setup screen (Esc),
## as buttons for the mouse, below the middle: under the winner and the credits card, above
## play mode's move bar.

signal rematch
signal menu

## How far below the middle of the screen the buttons sit.
const BELOW_MIDDLE := 200


func _init() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = MenuTheme.build()
	add_child(root)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", MenuTheme.plate())
	root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	bar.add_child(row)
	for choice: Array in [["Rematch  (R)", rematch], ["Menu  (Esc)", menu]]:
		var button := Button.new()
		button.text = choice[0]
		button.custom_minimum_size = Vector2(260, 64)
		button.add_theme_font_override("font", UiFonts.DISPLAY)
		button.add_theme_font_size_override("font_size", 32)
		var chosen: Signal = choice[1]
		button.pressed.connect(func() -> void: chosen.emit())
		row.add_child(button)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	bar.position.y += BELOW_MIDDLE
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.get_child(0).grab_focus.call_deferred()
