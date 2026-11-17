class_name MenuTheme
extends RefCounted
## The menus' look (the setup screen and the after-battle buttons): the HUD's dark rounded plates,
## side colours and gold (Hud), Nunito for controls and Lilita One for titles (UiFonts). Focus
## shows as a gold outline, so every control can be found from the keyboard.

const FONT_SIZE := 26
const BACKGROUND_TOP := Color(0.05, 0.07, 0.13)
const BACKGROUND_BOTTOM := Color(0.11, 0.14, 0.25)
const FIELD := Color(0.03, 0.04, 0.08, 0.92)
const BUTTON := Color(0.14, 0.17, 0.27)
const BUTTON_HOVER := Color(0.2, 0.24, 0.37)
const MUTED := Color(0.7, 0.74, 0.84)


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font = UiFonts.BODY
	theme.default_font_size = FONT_SIZE
	var focus := _box(Color(0, 0, 0, 0), 12)
	focus.draw_center = false
	focus.border_color = Hud.GOLD
	focus.set_border_width_all(3)
	focus.set_expand_margin_all(2)
	for type: String in ["Button", "OptionButton", "LineEdit", "ItemList", "SpinBox", "CheckBox"]:
		theme.set_stylebox("focus", type, focus)
	for type: String in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type, _box(BUTTON, 12))
		theme.set_stylebox("hover", type, _box(BUTTON_HOVER, 12))
		theme.set_stylebox("pressed", type, _box(Hud.GOLD.darkened(0.35), 12))
		theme.set_stylebox("hover_pressed", type, _box(Hud.GOLD.darkened(0.25), 12))
		theme.set_stylebox("disabled", type, _box(BUTTON.darkened(0.3), 12))
		theme.set_color("font_color", type, Color.WHITE)
		theme.set_color("font_hover_color", type, Color.WHITE)
		theme.set_color("font_pressed_color", type, Color.WHITE)
		theme.set_color("font_hover_pressed_color", type, Color.WHITE)
		theme.set_color("font_focus_color", type, Color.WHITE)
		theme.set_color("font_disabled_color", type, MUTED.darkened(0.3))
	theme.set_stylebox("normal", "LineEdit", _box(FIELD, 10))
	theme.set_stylebox("read_only", "LineEdit", _box(FIELD.darkened(0.3), 10))
	theme.set_color("font_placeholder_color", "LineEdit", MUTED.darkened(0.25))
	theme.set_color("caret_color", "LineEdit", Hud.GOLD)
	theme.set_stylebox("panel", "ItemList", _box(FIELD, 10))
	theme.set_stylebox("selected", "ItemList", _box(Hud.GOLD.darkened(0.45), 8))
	theme.set_stylebox("selected_focus", "ItemList", _box(Hud.GOLD.darkened(0.35), 8))
	theme.set_stylebox("hovered", "ItemList", _box(BUTTON_HOVER, 8))
	theme.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	theme.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	theme.set_color("font_color", "ItemList", MUTED)
	theme.set_color("font_selected_color", "ItemList", Color.WHITE)
	theme.set_constant("v_separation", "ItemList", 6)
	theme.set_stylebox("panel", "PopupMenu", _box(Color(0.06, 0.08, 0.14, 0.98), 10))
	theme.set_stylebox("hover", "PopupMenu", _box(BUTTON_HOVER, 8))
	theme.set_font_size("font_size", "PopupMenu", 24)
	theme.set_color("font_color", "Label", Color.WHITE)
	theme.set_stylebox("panel", "TooltipPanel", _box(Color(0.06, 0.08, 0.14, 0.98), 8))
	return theme


## A rounded box, padded for text.
static func _box(colour: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(radius)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box


## A side's panel: the HUD's plate, with the side's colour along its outer edge.
static func side_plate(side: int) -> StyleBoxFlat:
	var box := _box(Hud.PLATE, 20)
	box.border_color = Hud.SIDE_COLOURS[side]
	if side == 0:
		box.border_width_left = 8
	else:
		box.border_width_right = 8
	box.content_margin_left = 24
	box.content_margin_right = 24
	box.content_margin_top = 18
	box.content_margin_bottom = 18
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = 10
	return box


## A plain dark plate (the footer, the after-battle bar).
static func plate() -> StyleBoxFlat:
	var box := _box(Hud.PLATE, 20)
	box.content_margin_left = 24
	box.content_margin_right = 24
	box.content_margin_top = 14
	box.content_margin_bottom = 14
	return box


## A label in the display font with the HUD's dark outline.
static func title(text: String, font_size: int, colour := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiFonts.DISPLAY)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", maxi(6, font_size / 7))
	return label


## The vertical gradient behind the menus.
static func background() -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, BACKGROUND_TOP)
	gradient.set_color(1, BACKGROUND_BOTTOM)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	var rect := TextureRect.new()
	rect.texture = texture
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect
