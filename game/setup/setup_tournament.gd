class_name SetupTournament
extends PanelContainer
## The setup screen's tournament panel (concepts_brief.md §17, M19), shown in Tournament mode in
## place of the two sides: the bracket's size, games a match, team size, AI and field, and
## whether to record it as one video. It says what the bracket will be seeded by. The battle
## row below it (singles or doubles, arena, weather, seed) applies to every game.

signal changed

## The choices, matching SetupScreen.tournament_args(): "" for each one's default.
const DEFAULT := {"size": "", "best_of": "", "team_size": "", "ai": Controllers.DEFAULT_AI, "pool": "", "record": false}
const POOLS := {"": "Drawn from the top 4× (a new field each seed)", "top": "The top seeds", "all": "Drawn from every species"}

var _choices := DEFAULT.duplicate()
var _size: OptionButton
var _best_of: OptionButton
var _team_size: OptionButton
var _ai: OptionButton
var _pool: OptionButton
var _record: CheckBox


func _init() -> void:
	add_theme_stylebox_override("panel", MenuTheme.plate())
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	add_child(column)
	column.add_child(MenuTheme.title("Tournament", 48, Hud.GOLD))
	var about := _caption("A single-elimination bracket, seeded so the top two can only meet in the final. A card "
		+ "shows the bracket before each match and the champion at the end. Drawn games are replayed.")
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(about)
	var ranking := Tournament.find_ranking(ProjectSettings.globalize_path("res://results"), Controllers.DEFAULT_AI, Rules.RULES_VERSION)
	var seeding := Label.new()
	seeding.text = "Seeded by the ranking of rules v%d (%d battles)." % [ranking.rules, ranking.battles] if not ranking.is_empty() \
		else "No ranking yet (tools/rank.gd makes one): seeded by base stat total."
	column.add_child(seeding)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	column.add_child(grid)
	_size = _option(grid, "Entrants", "size")
	for size in Tournament.SIZES:
		_add(_size, str(size), "" if size == Tournament.DEFAULT_SIZE else str(size))
	_best_of = _option(grid, "Games a match", "best_of")
	for games in Tournament.BEST_OF:
		_add(_best_of, "Best of %d" % games, "" if games == 1 else str(games))
	_team_size = _option(grid, "Team size", "team_size")
	_add(_team_size, "One each (two in doubles)", "")
	for count in range(2, Rules.MAX_TEAM + 1):
		_add(_team_size, "Teams of %d" % count, str(count))
	_ai = _option(grid, "AI", "ai")
	for name in Cli.profiles():
		_add(_ai, name.capitalize(), name)
	_pool = _option(grid, "Field", "pool")
	for key: String in POOLS:
		_add(_pool, POOLS[key], key)
	grid.add_child(_caption("Video"))
	_record = CheckBox.new()
	_record.text = "Record it as one video (format and length below)"
	_record.toggled.connect(func(on: bool) -> void:
		_choices.record = on
		changed.emit())
	grid.add_child(_record)
	set_choices(DEFAULT)


func choices() -> Dictionary:
	return _choices.duplicate()


func set_choices(chosen: Dictionary) -> void:
	_choices = DEFAULT.duplicate()
	_choices.merge(chosen, true)
	for pair: Array in [[_size, "size"], [_best_of, "best_of"], [_team_size, "team_size"], [_ai, "ai"], [_pool, "pool"]]:
		_choose(pair[0], str(_choices[pair[1]]))
	_record.set_pressed_no_signal(bool(_choices.record))


func _option(grid: GridContainer, caption: String, key: String) -> OptionButton:
	grid.add_child(_caption(caption))
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.item_selected.connect(func(index: int) -> void:
		_choices[key] = str(option.get_item_metadata(index))
		changed.emit())
	grid.add_child(option)
	return option


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", MenuTheme.MUTED)
	return label


func _add(option: OptionButton, text: String, value: String) -> void:
	option.add_item(text)
	option.set_item_metadata(option.item_count - 1, value)


func _choose(option: OptionButton, value: String) -> void:
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			return
	option.select(0)
