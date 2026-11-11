class_name AIOverlay
extends CanvasLayer
## The AI debug overlay (concepts_brief.md §11): per side, the utility AI's candidate actions
## from its last decision, best first, each with a score bar and its considerations. The
## action it chose is highlighted. It only reads the scores the AI keeps when asked
## (UtilityAI.keep_scores), so showing it never changes a battle.

const ROWS := 6
const REFERENCE_SIZE := 1080.0
## Short names for considerations, so a row fits on one line.
const SHORT_NAMES := {
	"in_range": "range", "damage": "dmg", "finisher": "fin", "safe_to_commit": "safe", "value": "val",
	"urgency": "urg", "charges": "chg", "danger": "dgr", "too_far": "far", "too_close": "close", "base": "base", "cover": "cover", "stage_cost": "cost",
}
const CHOSEN := Color(1.0, 0.85, 0.3)
const OTHER := Color(0.85, 0.9, 1.0)

var _panels: Array[Dictionary] = []
var _controllers: Array = []
var _scale := 1.0
var _size := Vector2.ZERO
var _portrait := false
## Space kept clear of the screen edge.
const MARGIN := 40.0


## `controllers` are the battle's two controllers; `names` label the panels. Panels sit under
## each side's HUD bar (`hud_bands`: the top and bottom band heights).
func setup(controllers: Array, names: Array, viewport_size: Vector2, hud_bands: Vector2) -> void:
	_controllers = controllers
	_size = viewport_size
	_scale = minf(viewport_size.x, viewport_size.y) / REFERENCE_SIZE
	var portrait := VideoFormat.is_portrait(viewport_size)
	_portrait = portrait
	var width := viewport_size.x * (0.9 if portrait else 0.38)
	for side in 2:
		var controller: Object = controllers[side]
		if controller is UtilityAI:
			(controller as UtilityAI).keep_scores = true
		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0.55)
		style.set_corner_radius_all(roundi(8 * _scale))
		style.set_content_margin_all(10 * _scale)
		panel.add_theme_stylebox_override("panel", style)
		panel.custom_minimum_size.x = width
		# Below the HP bars and the move banners under them.
		var top := hud_bands.x * _scale + 60 * _scale
		if portrait:
			panel.position = Vector2((viewport_size.x - width) * 0.5,
				top if side == 1 else viewport_size.y * 0.55)
		else:
			panel.position = Vector2(MARGIN * _scale if side == 0 else viewport_size.x - width - MARGIN * _scale, top)
		add_child(panel)
		var rows := VBoxContainer.new()
		panel.add_child(rows)
		var title := _label("%s · %s" % [names[side], describe_controller(controller)], 24, Color.WHITE)
		rows.add_child(title)
		var lines: Array[Label] = []
		for i in ROWS:
			var line := _label("", 19, OTHER)
			rows.add_child(line)
			lines.append(line)
		_panels.append({"panel": panel, "lines": lines})


## Refreshes the rows from each AI's latest scores. Cheap enough to run every frame.
func refresh() -> void:
	for side in _panels.size():
		var lines: Array[Label] = _panels[side].lines
		var controller: Object = _controllers[side]
		var scores: Array = controller.last_scores if controller is UtilityAI else []
		var chosen: String = (controller as UtilityAI)._current if controller is UtilityAI else ""
		for i in lines.size():
			var line := lines[i]
			if i >= scores.size():
				line.text = "" if i > 0 or controller is UtilityAI else "no scores (stand-in AI)"
				continue
			line.text = describe(scores[i])
			line.add_theme_color_override("font_color", CHOSEN if scores[i].action == chosen else OTHER)
		# The right-hand panel grows with its text, so keep it against the screen's right edge.
		if not _portrait and side == 1:
			var panel: PanelContainer = _panels[side].panel
			panel.position.x = _size.x - MARGIN * _scale - panel.get_combined_minimum_size().x


## "simple" or the profile's name.
static func describe_controller(controller: Object) -> String:
	if controller is UtilityAI:
		return "AI %s" % (controller as UtilityAI).profile.resource_path.get_file().get_basename()
	return "AI simple"


## One candidate as a row: action, a ten-step score bar, the score and its considerations.
static func describe(candidate: Dictionary) -> String:
	var score: float = candidate.score
	var filled := clampi(roundi(score * 10.0), 0, 10)
	var bar := "█".repeat(filled) + "·".repeat(10 - filled)
	var parts: PackedStringArray = []
	for name: String in candidate.considerations:
		parts.append("%s %.2f" % [SHORT_NAMES.get(name, name), float(candidate.considerations[name])])
	return "%-16s %s %.2f  %s" % [str(candidate.action).trim_prefix("move:"), bar, score, " · ".join(parts)]


func _label(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", roundi(font_size * _scale))
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", roundi(6 * _scale))
	return label
