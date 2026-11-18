class_name HudBadge
extends Control
## A square dark badge in a name plate's effect row (concepts_brief.md §12.5): a pixel-art icon,
## then short texts (a status code, or a stat and its stage count), edged in the effect's colour,
## with an optional timer draining along its bottom. Sizes are in reference pixels (Hud's 1080).

const HEIGHT := 48.0
const PIXEL := 4.0
const PAD := 8.0
const GAP := 5.0
const BORDER := 3.0
const TIMER_HEIGHT := 4.0
const FONT_SIZE := 28
const BACKGROUND := Color(0.04, 0.05, 0.09, 0.9)

## Icons drawn in-house, one string per row: "#" the colour, "+" a lighter shade, "w" near
## white, "o" a dark shade, "." clear.
const ICONS := {
	"brn": [
		"....o....",
		"...o#o...",
		"...o#o...",
		"..o#+#o..",
		".o#+++#o.",
		".o#+w+#o.",
		"o#++w++#o",
		".o#+++#o.",
		"..ooooo..",
	],
	"par": [
		".....ooo.",
		"....o##o.",
		"...o#+o..",
		"..o#+###o",
		".o###+#o.",
		"...o#+o..",
		"..o#+o...",
		".o##o....",
		".ooo.....",
	],
	"psn": [
		"....o....",
		"...o#o...",
		"..o###o..",
		"..o#+#o..",
		".o#+w##o.",
		".o#+w##o.",
		".o#####o.",
		"..o###o..",
		"...ooo...",
	],
	"tox": [
		"..ooooo..",
		".o#####o.",
		"o###+###o",
		"o#oo#oo#o",
		"o#oo#oo#o",
		".o##o##o.",
		"..o###o..",
		"..o#o#o..",
		"...ooo...",
	],
	"slp": [
		"ooooooooo",
		"o#######o",
		"ooooo##oo",
		"...o##o..",
		"..o##o...",
		".o##o....",
		"oo##ooooo",
		"o#######o",
		"ooooooooo",
	],
	"frz": [
		"....#....",
		".#..+..#.",
		"..#.+.#..",
		"...+w+...",
		"#++www++#",
		"...+w+...",
		"..#.+.#..",
		".#..+..#.",
		"....#....",
	],
	"confusion": [
		"..#####..",
		".#.....#.",
		"#..+++..#",
		"#.+...+.#",
		"#.+.w.+.#",
		"#.+..+..#",
		"#..++...#",
		".#.....#.",
		"..####...",
	],
	"reflect": [
		"#########",
		"#+++++++#",
		"#+wwwww+#",
		"#+w+++w+#",
		".#+w+w+#.",
		".#+w+w+#.",
		"..#+w+#..",
		"...#+#...",
		"....#....",
	],
	"lightscreen": [
		"#########",
		"#+++++w+#",
		"#++++w++#",
		"#+++w+++#",
		"#++w+++w#",
		"#+w+++w+#",
		"#w+++w++#",
		"#+++w+++#",
		"#########",
	],
	"auroraveil": [
		"..#####..",
		".#.....#.",
		"#..+++..#",
		"#.+...+.#",
		"#.+.w.+.#",
		"#.+.w.+.#",
		"#.+.w.+.#",
		"#.+.w.+.#",
		"#.+.w.+.#",
	],
	"stealthrock": [
		".........",
		"..o...o..",
		".o#o.o+o.",
		".o##o##o.",
		"..oo.oo..",
		"...ooo...",
		"..o+##o..",
		".o#####o.",
		"..ooooo..",
	],
	"spikes": [
		".........",
		".........",
		"....o....",
		"...o+o...",
		"..o+#o...",
		".o+##o.o.",
		".o###oo+o",
		"o#####o#o",
		"ooooooooo",
	],
	"toxicspikes": [
		".........",
		"....o....",
		"...o+o...",
		"..o+w#o..",
		"..o+##o..",
		".o+###o..",
		".o#####o.",
		"o#######o",
		"ooooooooo",
	],
	"stickyweb": [
		"o...o...o",
		".o..o..o.",
		"..o+#+o..",
		"..+o#o+..",
		"oo##w##oo",
		"..+o#o+..",
		"..o+#+o..",
		".o..o..o.",
		"o...o...o",
	],
	"up": [
		"...#...",
		"..#+#..",
		".#+w+#.",
		"###w###",
		"..#w#..",
		"..#w#..",
		"..###..",
	],
	"down": [
		"..###..",
		"..#w#..",
		"..#w#..",
		"###w###",
		".#+w+#.",
		"..#+#..",
		"...#...",
	],
}

var _scale := 1.0
var _colour := Color.WHITE
var _timer: ColorRect
var _timer_width := 0.0


## A badge edged in `colour`: `parts` in order, each an icon name from ICONS or a text, with
## the colour to draw it in: [[part, colour], ...]. `timed` adds the draining timer.
func _init(parts: Array, colour: Color, timed: bool, hud_scale: float) -> void:
	_scale = hud_scale
	_colour = colour
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var x := (PAD + BORDER) * _scale
	for i in parts.size():
		var part: String = parts[i][0]
		var part_colour: Color = parts[i][1]
		if i > 0:
			x += GAP * _scale
		var item: Control
		if ICONS.has(part):
			item = PixelIcon.new(ICONS[part], part_colour, PIXEL * _scale)
		else:
			var label := Label.new()
			label.text = part
			label.add_theme_font_override("font", UiFonts.DISPLAY)
			label.add_theme_font_size_override("font_size", roundi(FONT_SIZE * _scale))
			label.add_theme_color_override("font_color", part_colour)
			label.add_theme_color_override("font_outline_color", Color.BLACK)
			label.add_theme_constant_override("outline_size", roundi(6 * _scale))
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# Measured from the font itself: outside the tree a label's minimum size ignores
			# its font override.
			var font_size := roundi(FONT_SIZE * _scale)
			label.size = Vector2(UiFonts.DISPLAY.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x,
				UiFonts.DISPLAY.get_height(font_size))
			item = label
		item.position = Vector2(x, (HEIGHT * _scale - item.size.y) * 0.5 - (TIMER_HEIGHT * 0.5 if timed else 0.0) * _scale)
		add_child(item)
		x += item.size.x
	size = Vector2(x + (PAD + BORDER) * _scale, HEIGHT * _scale)
	custom_minimum_size = size
	if timed:
		_timer_width = size.x - 2.0 * BORDER * _scale
		_timer = ColorRect.new()
		_timer.color = colour
		_timer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_timer.position = Vector2(BORDER, HEIGHT - BORDER - TIMER_HEIGHT) * _scale
		_timer.size = Vector2(_timer_width, TIMER_HEIGHT * _scale)
		add_child(_timer)


## Drains the timer to `left`, the share of the effect's time left.
func set_left(left: float) -> void:
	if _timer != null:
		_timer.size.x = _timer_width * clampf(left, 0.0, 1.0)


## The timer's current share, or -1 for a badge without one.
func left() -> float:
	return _timer.size.x / _timer_width if _timer != null else -1.0


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, BACKGROUND)
	draw_rect(rect.grow(-BORDER * _scale * 0.5), _colour, false, BORDER * _scale)


## An icon from ICONS drawn as square pixels.
class PixelIcon:
	extends Control

	var _rows: Array
	var _colour: Color
	var _pixel: float

	func _init(rows: Array, colour: Color, pixel: float) -> void:
		_rows = rows
		_colour = colour
		_pixel = pixel
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2((rows[0] as String).length(), rows.size()) * pixel
		custom_minimum_size = size

	func _draw() -> void:
		var shades := {"#": _colour, "+": _colour.lightened(0.45), "w": Color(1, 1, 0.95), "o": _colour.darkened(0.6)}
		for y in _rows.size():
			var row: String = _rows[y]
			for x in row.length():
				var shade: Variant = shades.get(row[x])
				if shade != null:
					draw_rect(Rect2(Vector2(x, y) * _pixel, Vector2.ONE * _pixel), shade)
