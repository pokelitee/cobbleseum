class_name Hud
extends CanvasLayer
## The battle HUD (concepts_brief.md §12.1, §12.5): a name plate per fighter (its name, type
## pills, status badges, and a rounded HP bar with a lagging damage segment and its percentage),
## move-name banners, and the intro, victory, winner and credits cards, in the game's fonts
## (UiFonts).
## Layout follows the orientation: portrait has side B at the top and side A at the bottom;
## landscape has side A top-left and side B top-right. Everything animates per video frame.

## Frames before the lagging segment starts draining, and its drain per frame (share of bar).
const LAG_DELAY := 12
const LAG_DRAIN := 0.02
const SHAKE_FRAMES := 10
const SHAKE_PIXELS := 14.0
const BANNER_FRAMES := 50
const INTRO_FRAMES := 50
const CREDITS_FRAMES := 60
const REFERENCE_SIZE := 1080.0
const HEALTHY := Color(0.3, 0.9, 0.4)
const WARNING := Color(1.0, 0.8, 0.2)
const DANGER := Color(1.0, 0.3, 0.25)
## Each side's accent (the plate's edge, the intro's names), like the stadium's banners.
const SIDE_COLOURS: Array[Color] = [Color(0.92, 0.3, 0.26), Color(0.26, 0.52, 0.96)]
const PLATE := Color(0.06, 0.08, 0.14, 0.8)
const GOLD := Color(1.0, 0.86, 0.32)
## The plate reaches this far around the name and bar, and the bar sits this far down.
const PLATE_PAD := Vector2(18, 12)
const BAR_TOP := 80.0
const BAR_HEIGHT := 36.0
## Banners sit this far below the panel's origin (above it for portrait's bottom plate).
const BANNER_BELOW := 150.0
const BANNER_ABOVE := -86.0
## Uses a non-breaking hyphen so the licence name never wraps mid-word.
## Badge text and colour per status condition.
const STATUS_BADGES := {
	"brn": ["BRN", Color("ff7a2e")], "par": ["PAR", Color("e8c21c")], "psn": ["PSN", Color("b45ad6")],
	"tox": ["TOX", Color("8e3fb0")], "slp": ["SLP", Color("8a8a9a")], "frz": ["FRZ", Color("5cc8e0")],
	"confusion": ["CNF", Color("ff5f9e")],
}
const CREDITS_TEXT := "Models, animations and sounds: Cobblemon (CC BY‑NC 3.0)\nBattle data: Pokémon Showdown\nAn unaffiliated, non-commercial fan project"

var _size := Vector2.ZERO
var _scale := 1.0
var _portrait := false
var _panels: Array[Control] = []
var _panel_homes: Array[Vector2] = []
var _bars: Array[ColorRect] = []
var _lags: Array[ColorRect] = []
var _percents: Array[Label] = []
## HP fractions as last set. Kept here because a Control's scale can't reach exactly 0.
var _hp_values: Array[float] = [1.0, 1.0]
var _lag_values: Array[float] = [1.0, 1.0]
var _lag_waits: Array[int] = [0, 0]
var _shakes: Array[int] = [0, 0]
var _banners: Array[Dictionary] = []
## Per side: status -> badge label, laid out in a row after the name.
var _badge_rows: Array[HBoxContainer] = []
var _badges: Array[Dictionary] = [{}, {}]
var _intro: Control
var _intro_age := 0
var _winner: Label
var _winner_band: ColorRect
## The victory card, sliding in from the left, and frames since it appeared.
var _victory: Control
var _victory_age := -1
var _credits: Control
## Play mode's move bar: per move {"panel", "shade"} (the shade covers it while cooling down).
var _move_slots: Array[Dictionary] = []
var _hint: Label
## Flashed titles: {"label": Label, "age": frames}.
var _titles: Array[Dictionary] = []
const TITLE_FRAMES := 45
## The victory card slides in over this many frames while the name plates fade out.
const VICTORY_IN_FRAMES := 12
var _frame := 0


## Builds the HUD for fighters `names` (side A first), with each one's `types` for its pills.
func setup(names: Array, viewport_size: Vector2, types: Array = [[], []]) -> void:
	_size = viewport_size
	_portrait = VideoFormat.is_portrait(viewport_size)
	_scale = minf(viewport_size.x, viewport_size.y) / REFERENCE_SIZE
	var margin := 60.0 * _scale
	var bar_width := viewport_size.x - 2 * margin if _portrait else viewport_size.x * 0.4
	for side in 2:
		var panel := Control.new()
		var home: Vector2
		if _portrait:
			home = Vector2(margin, (90 if side == 1 else viewport_size.y / _scale - 220) * _scale)
		else:
			home = Vector2(margin if side == 0 else viewport_size.x - margin - bar_width, 40 * _scale)
		panel.position = home
		add_child(panel)
		# Mirror the right-hand landscape plate so its bar drains toward the centre of the screen.
		var mirrored := not _portrait and side == 1
		var plate := Panel.new()
		plate.position = -PLATE_PAD * _scale
		plate.size = (Vector2(bar_width / _scale, BAR_TOP + BAR_HEIGHT) + PLATE_PAD * 2.0) * _scale
		plate.add_theme_stylebox_override("panel", _plate_style(side, mirrored))
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(plate)
		var name_label := _label(names[side], 56, Color.WHITE, true)
		panel.add_child(name_label)
		# Type pills, then status badges as they come and go.
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", roundi(8 * _scale))
		row.position = Vector2(name_label.get_minimum_size().x + 16 * _scale, 14 * _scale)
		panel.add_child(row)
		var own_types: Array = types[side] if side < types.size() else []
		for type: String in own_types:
			row.add_child(_pill(type.to_upper(), TypeColors.of(type)))
		_badge_rows.append(row)
		var track := Panel.new()
		track.position = Vector2(0, BAR_TOP) * _scale
		track.size = Vector2(bar_width / _scale, BAR_HEIGHT) * _scale
		var track_style := StyleBoxFlat.new()
		track_style.bg_color = Color(0, 0, 0, 0.6)
		track_style.set_corner_radius_all(roundi(BAR_HEIGHT * 0.5 * _scale))
		track.add_theme_stylebox_override("panel", track_style)
		# The bar's ends take the track's rounded shape.
		track.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(track)
		var lag := _rect(Color(1, 0.95, 0.85), Vector2.ZERO, Vector2(bar_width / _scale, BAR_HEIGHT))
		var bar := _rect(HEALTHY, Vector2.ZERO, Vector2(bar_width / _scale, BAR_HEIGHT))
		# A light band along the top of the bar, so it reads as rounded rather than flat.
		bar.add_child(_rect(Color(1, 1, 1, 0.22), Vector2(0, 4), Vector2(bar_width / _scale, BAR_HEIGHT * 0.3)))
		for rect in [lag, bar]:
			if mirrored:
				rect.pivot_offset = Vector2(rect.size.x, 0)
			track.add_child(rect)
		var percent := _label("100%", 26, Color.WHITE)
		percent.add_theme_constant_override("outline_size", roundi(8 * _scale))
		percent.size = Vector2(track.size.x - 24 * _scale, track.size.y)
		percent.position = Vector2(12 * _scale, 0)
		percent.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if mirrored else HORIZONTAL_ALIGNMENT_RIGHT
		track.add_child(percent)
		_panels.append(panel)
		_panel_homes.append(home)
		_bars.append(bar)
		_lags.append(lag)
		_percents.append(percent)
	var credit := _label("Models, animations and sounds: Cobblemon (CC BY-NC 3.0)", 28, Color.WHITE)
	credit.position = Vector2(margin, viewport_size.y - 60 * _scale)
	add_child(credit)
	_intro = _matchup(names)
	_winner_band = ColorRect.new()
	_winner_band.color = Color(0.04, 0.05, 0.1, 0.72)
	_winner_band.size = Vector2(viewport_size.x, 190 * _scale)
	_winner_band.position = Vector2(0, viewport_size.y * 0.42 - _winner_band.size.y * 0.5)
	_winner_band.visible = false
	add_child(_winner_band)
	_winner = _label("", 110, GOLD, true)
	_winner.add_theme_constant_override("outline_size", roundi(16 * _scale))
	_winner.visible = false
	add_child(_winner)
	_credits = _card(CREDITS_TEXT, 44, 0.85)
	_credits.visible = false


## Sets the HP fraction shown for a side. The lagging segment holds, then drains to match;
## `immediate` skips the lag (e.g. when a clip starts mid-battle).
func set_hp(side: int, fraction: float, immediate := false) -> void:
	var bar := _bars[side]
	if immediate:
		_lag_values[side] = fraction
		_lags[side].scale.x = fraction
	elif fraction < _hp_values[side]:
		_lag_waits[side] = LAG_DELAY
	_hp_values[side] = fraction
	bar.scale.x = fraction
	_percents[side].text = "%d%%" % ceili(fraction * 100.0 - 1e-6)
	bar.color = HEALTHY if fraction > 0.5 else (WARNING if fraction > 0.2 else DANGER)


## Shows or hides a status badge ("brn", ..., or "confusion") beside a fighter's name.
func set_status(side: int, status: String, active: bool) -> void:
	if _badges[side].has(status):
		_badges[side][status].queue_free()
		_badges[side].erase(status)
	if not active or not STATUS_BADGES.has(status):
		return
	var badge := _pill(STATUS_BADGES[status][0], STATUS_BADGES[status][1])
	_badge_rows[side].add_child(badge)
	_badges[side][status] = badge


func shake(side: int) -> void:
	_shakes[side] = SHAKE_FRAMES


## Shows the move's name in a banner under the fighter's HP bar, tinted by its type.
func banner(side: int, move_name: String, type: String) -> void:
	var tag := Label.new()
	tag.text = " %s " % move_name
	tag.add_theme_font_override("font", UiFonts.DISPLAY)
	tag.add_theme_font_size_override("font_size", roundi(40 * _scale))
	tag.add_theme_color_override("font_color", Color.WHITE)
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	tag.add_theme_constant_override("outline_size", roundi(8 * _scale))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(TypeColors.of(type), 0.85)
	style.set_corner_radius_all(roundi(14 * _scale))
	style.content_margin_left = 10 * _scale
	style.content_margin_right = 10 * _scale
	tag.add_theme_stylebox_override("normal", style)
	_panels[side].add_child(tag)
	tag.size = tag.get_minimum_size()  # measured once the theme applies, inside the tree
	var right_aligned := not _portrait and side == 1
	var bar_width := _bars[side].size.x
	tag.position = Vector2(bar_width - tag.size.x if right_aligned else 0.0, BANNER_BELOW * _scale)
	if _portrait and side == 0:
		tag.position.y = BANNER_ABOVE * _scale  # above the bottom plate, not off the screen
	for old in _banners.filter(func(b: Dictionary) -> bool: return b.side == side):
		old.label.queue_free()
		_banners.erase(old)
	_banners.append({"label": tag, "side": side, "age": 0})


func show_winner(text: String) -> void:
	_winner.text = text
	_winner.size = _winner.get_minimum_size()
	_winner.position = (_size - _winner.size) * Vector2(0.5, 0.42)
	_winner.pivot_offset = _winner.size * 0.5
	_winner.visible = true
	_winner.scale = Vector2.ONE * 1.6
	_winner_band.visible = true


## The victory card across the lower part of the screen: "WINNER", the winner's name outlined
## in its side's colour, and its HP left and the battle's length. The name plates fade out.
func show_victory(side: int, name: String, hp_share: float, seconds: float) -> void:
	var height := 260.0 * _scale
	_victory = Control.new()
	_victory.size = Vector2(_size.x, height)
	# Below the winner, whom the victory shot frames in the middle, and above the credit line.
	_victory.position = Vector2(-_size.x, _size.y * (0.74 if _portrait else 0.78) - height * 0.5)
	_victory.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_victory)
	_victory.add_child(_rect(Color(0.04, 0.05, 0.1, 0.78), Vector2.ZERO, _victory.size / _scale))
	_victory.add_child(_rect(SIDE_COLOURS[side], Vector2.ZERO, Vector2(_size.x / _scale, 8)))
	_victory.add_child(_rect(SIDE_COLOURS[side], Vector2(0, height / _scale - 8), Vector2(_size.x / _scale, 8)))
	var lines := VBoxContainer.new()
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.add_theme_constant_override("separation", roundi(-6 * _scale))
	_victory.add_child(lines)
	var heading := _label("WINNER", 48, GOLD, true)
	var title := _label(name, 120, Color.WHITE, true)
	title.add_theme_color_override("font_outline_color", SIDE_COLOURS[side].darkened(0.35))
	title.add_theme_constant_override("outline_size", roundi(20 * _scale))
	var total := roundi(seconds)
	var stats := _label("%d%% HP left  ·  %d:%02d" % [ceili(hp_share * 100.0 - 1e-6), total / 60, total % 60], 36, Color(0.88, 0.9, 0.95))
	for label: Label in [heading, title, stats]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lines.add_child(label)
	lines.size = Vector2(_size.x, height)
	_victory_age = 0


## A title flashed in the middle of the screen, e.g. "Overtime!".
func flash_title(text: String, colour: Color) -> void:
	var title := _label(text, 96, colour, true)
	title.size = title.get_minimum_size()
	title.position = (_size - title.size) * Vector2(0.5, 0.35)
	add_child(title)
	_titles.append({"label": title, "age": 0})


## Play mode: the player's moves along the bottom, each with its key and a cooldown shade.
func show_move_bar(names: Array, types: Array, keys: Array) -> void:
	var slot_width := 300.0 * _scale
	var gap := 16.0 * _scale
	var total := names.size() * slot_width + (names.size() - 1) * gap
	for i in names.size():
		var panel := ColorRect.new()
		panel.color = Color(TypeColors.of(types[i]), 0.85)
		panel.size = Vector2(slot_width, 70 * _scale)
		panel.position = Vector2((_size.x - total) * 0.5 + i * (slot_width + gap), _size.y - 170 * _scale)
		add_child(panel)
		var label := _label("%s  %s" % [keys[i], names[i]], 30, Color.WHITE)
		label.position = Vector2(12, 14) * _scale
		panel.add_child(label)
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.6)
		shade.size = panel.size
		panel.add_child(shade)
		_move_slots.append({"panel": panel, "shade": shade})


## Shades each move by how much of its cooldown is left.
func update_move_bar(fighter: Fighter) -> void:
	for i in _move_slots.size():
		var shade: ColorRect = _move_slots[i].shade
		var total := maxi(fighter.moves[i].cooldown_ticks, 1)
		shade.scale.x = clampf(float(fighter.cooldowns[i]) / total, 0.0, 1.0)


## A line of help text along the bottom of the screen; "" hides it.
func show_hint(text: String) -> void:
	if _hint == null:
		_hint = _label("", 32, Color.WHITE)
		add_child(_hint)
	_hint.text = text
	_hint.size = _hint.get_minimum_size()
	_hint.position = Vector2((_size.x - _hint.size.x) * 0.5, _size.y - 180 * _scale - _hint.size.y)  # above the move bar


func show_credits() -> void:
	if _victory != null:
		_victory.visible = false
	_credits.visible = true
	_credits.modulate.a = 0.0


## Advances every animation by one video frame.
func next_frame() -> void:
	_frame += 1
	for side in 2:
		if _lag_waits[side] > 0:
			_lag_waits[side] -= 1
		else:
			_lag_values[side] = maxf(_hp_values[side], _lag_values[side] - LAG_DRAIN)
		_lags[side].scale.x = _lag_values[side]
		var offset := Vector2.ZERO
		if _shakes[side] > 0:
			_shakes[side] -= 1
			var strength := SHAKE_PIXELS * _scale * _shakes[side] / SHAKE_FRAMES
			offset = Vector2(sin(_frame * 3.1), sin(_frame * 4.7)) * strength
		_panels[side].position = _panel_homes[side] + offset
	for banner_data in _banners.duplicate():
		banner_data.age += 1
		var label: Label = banner_data.label
		label.modulate.a = clampf(minf(banner_data.age / 4.0, (BANNER_FRAMES - banner_data.age) / 8.0), 0.0, 1.0)
		if banner_data.age >= BANNER_FRAMES:
			label.queue_free()
			_banners.erase(banner_data)
	if _intro.visible:
		_intro_age += 1
		_intro.modulate.a = clampf((INTRO_FRAMES - _intro_age) / 10.0, 0.0, 1.0)
		_intro.visible = _intro_age < INTRO_FRAMES
	if _winner.visible:
		_winner.scale = _winner.scale.lerp(Vector2.ONE, 0.25)
	if _victory_age >= 0:
		_victory_age += 1
		var t := ease(clampf(_victory_age / float(VICTORY_IN_FRAMES), 0.0, 1.0), 0.3)
		_victory.position.x = lerpf(-_size.x, 0.0, t)
		for panel in _panels:
			panel.modulate.a = 1.0 - t
	if _credits.visible:
		_credits.modulate.a = minf(1.0, _credits.modulate.a + 0.1)
	for title in _titles.duplicate():
		title.age += 1
		var label: Label = title.label
		label.modulate.a = clampf((TITLE_FRAMES - title.age) / 10.0, 0.0, 1.0)
		if title.age >= TITLE_FRAMES:
			label.queue_free()
			_titles.erase(title)


func _card(text: String, font_size: int, dim: float) -> Control:
	var card := Control.new()
	card.size = _size
	add_child(card)
	if dim > 0.0:
		card.add_child(_rect(Color(0, 0, 0, dim), Vector2.ZERO, _size / _scale))
	var label := _label(text, font_size, Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var margin := 60.0 * _scale
	card.add_child(label)
	label.size = Vector2(_size.x - 2 * margin, 0)
	label.size.y = label.get_minimum_size().y
	label.position = Vector2(margin, (_size.y - label.size.y) * 0.5)
	return card


## The intro card: the two names in their sides' colours either side of a gold "VS", across
## the middle (stacked in portrait).
func _matchup(names: Array) -> Control:
	var card := Control.new()
	card.size = _size
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)
	var box := BoxContainer.new()
	box.vertical = _portrait
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", roundi(36 * _scale))
	card.add_child(box)
	for part: Array in [[names[0], 0], ["VS", -1], [names[1], 1]]:
		var vs: bool = part[1] < 0
		var label := _label(part[0], 132 if vs else 104, GOLD if vs else Color.WHITE, true)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_outline_color", Color.BLACK if vs else SIDE_COLOURS[part[1]].darkened(0.35))
		label.add_theme_constant_override("outline_size", roundi(20 * _scale))
		box.add_child(label)
	box.size = box.get_minimum_size()
	box.position = (_size - box.size) * 0.5
	return card


## A small rounded tag: a type or a status condition.
func _pill(text: String, colour: Color) -> Label:
	var pill := _label(text, 24, Color.WHITE)
	pill.add_theme_constant_override("outline_size", roundi(6 * _scale))
	pill.add_theme_color_override("font_outline_color", colour.darkened(0.5))
	var style := StyleBoxFlat.new()
	style.bg_color = colour
	style.set_corner_radius_all(roundi(14 * _scale))
	style.content_margin_left = 12 * _scale
	style.content_margin_right = 12 * _scale
	style.content_margin_top = 2 * _scale
	style.content_margin_bottom = 2 * _scale
	pill.add_theme_stylebox_override("normal", style)
	return pill


## A fighter's plate: dark and rounded, with a stripe of the side's colour on its outer edge.
func _plate_style(side: int, mirrored: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PLATE
	style.set_corner_radius_all(roundi(20 * _scale))
	style.border_color = SIDE_COLOURS[side]
	if mirrored:
		style.border_width_right = roundi(8 * _scale)
	else:
		style.border_width_left = roundi(8 * _scale)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = roundi(10 * _scale)
	return style


## A label in the body font, or the display font with `display`.
func _label(text: String, font_size: int, colour: Color, display := false) -> Label:
	var label := Label.new()
	label.text = text
	if display:
		label.add_theme_font_override("font", UiFonts.DISPLAY)
	label.add_theme_font_size_override("font_size", roundi(font_size * _scale))
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", roundi(12 * _scale))
	return label


func _rect(colour: Color, position: Vector2, size: Vector2) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = colour
	rect.position = position * _scale
	rect.size = size * _scale
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect
