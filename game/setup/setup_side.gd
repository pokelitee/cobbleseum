class_name SetupSide
extends PanelContainer
## One side of the setup screen: a searchable species list with a model preview, and the
## fighter's form, shiny, ability, item, moves and AI. Each choice defaults to what a battle from
## flags does without it (standard moves, ability and item; looks rolled from the seed).
## It edits one team member; team battles (M15) add a row of slots above it that picks which.

signal changed

## The member's keys, matching SetupScreen.flags_for(): "" for each one's default.
## A side's choices: its first member's species and settings, its AI, and "bench", the rest of
## its team (team battles) as comma-separated species IDs.
const DEFAULT_MEMBER := {"species": "", "form": "", "shiny": "", "ability": "", "item": "", "moves": "", "ai": Controllers.DEFAULT_AI,
	"bench": ""}
const ROLLED := "Rolled by the seed"
const SHINY_CHOICES := {"": ROLLED, "no": "No", "yes": "Yes"}
const PREVIEW_DELAY := 0.15
const LIST_WIDTH := 340

var side := 0
var _data: BattleData
## [display name, ID] of every species a battle can use, by name.
var _species: Array = []
var _member := DEFAULT_MEMBER.duplicate()
var _search: LineEdit
var _list: ItemList
var _name: Label
var _types: HBoxContainer
var _preview: ModelPreview
var _form: OptionButton
var _shiny: OptionButton
var _ability: OptionButton
var _item: OptionButton
var _ai: OptionButton
var _moves: LineEdit
var _moves_hint: Label
var _preview_wait := -1.0
var _player := false
## Team slots: buttons for the first member and the bench, the slot being picked (0 for the
## first member, whose settings the details edit), and the details grid, which bench members
## don't use (they bring their standard moves, ability and item).
var _slot_buttons: Array[Button] = []
var _slot := 0
var _grid: GridContainer
var _bench_hint: Label


func _init(side_index: int, data: BattleData) -> void:
	side = side_index
	_data = data
	for id: String in Cli.species_ids(data):
		_species.append([str(data.species[id].get("name", id)), id])
	_species.sort_custom(func(a: Array, b: Array) -> bool: return a[0].naturalnocasecmp_to(b[0]) < 0)
	add_theme_stylebox_override("panel", MenuTheme.side_plate(side))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	column.add_child(header)
	var tag := MenuTheme.title("Side %s" % "AB"[side], 30, Hud.SIDE_COLOURS[side].lightened(0.2))
	header.add_child(tag)
	_name = MenuTheme.title("", 48)
	header.add_child(_name)
	_types = HBoxContainer.new()
	_types.add_theme_constant_override("separation", 8)
	_types.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(_types)

	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 6)
	column.add_child(slots)
	slots.add_child(_caption("Team"))
	for i in Rules.MAX_TEAM:
		var button := Button.new()
		button.toggle_mode = true
		button.clip_text = true
		button.custom_minimum_size.x = 92
		button.tooltip_text = "Pick this team slot's species from the list"
		button.pressed.connect(_pick_slot.bind(i))
		slots.add_child(button)
		_slot_buttons.append(button)
	var remove := Button.new()
	remove.text = "Remove"
	remove.tooltip_text = "Takes the selected bench member out of the team"
	remove.pressed.connect(_remove_slot)
	slots.add_child(remove)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	var picker := VBoxContainer.new()
	picker.custom_minimum_size.x = LIST_WIDTH
	picker.add_theme_constant_override("separation", 8)
	body.add_child(picker)
	_search = LineEdit.new()
	_search.placeholder_text = "Search species…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_text: String) -> void: _filter())
	_search.text_submitted.connect(func(_text: String) -> void: _pick_first())
	_search.gui_input.connect(_on_search_input)
	picker.add_child(_search)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_species_selected)
	picker.add_child(_list)

	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 8)
	body.add_child(details)
	_preview = ModelPreview.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size.y = 240
	details.add_child(_preview)
	_bench_hint = _caption("Bench members bring their standard moves, ability and item.")
	_bench_hint.visible = false
	details.add_child(_bench_hint)
	var grid := GridContainer.new()
	_grid = grid
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	details.add_child(grid)
	_ai = _option(grid, "AI")
	for name in Cli.profiles():
		_add(_ai, name.capitalize(), name)
	_add(_ai, "Stand-in", "stand_in")
	_form = _option(grid, "Form")
	_shiny = _option(grid, "Shiny")
	for key: String in SHINY_CHOICES:
		_add(_shiny, SHINY_CHOICES[key], key)
	_ability = _option(grid, "Ability")
	_item = _option(grid, "Item")
	grid.add_child(_caption("Moves"))
	_moves = LineEdit.new()
	_moves.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_moves.placeholder_text = "Standard"
	_moves.tooltip_text = "Up to four moves, separated by commas; empty for the standard moveset"
	_moves.text_changed.connect(func(text: String) -> void: _change("moves", text.strip_edges()))
	grid.add_child(_moves)
	grid.add_child(Control.new())
	_moves_hint = Label.new()
	_moves_hint.add_theme_font_size_override("font_size", 20)
	_moves_hint.add_theme_color_override("font_color", MenuTheme.MUTED)
	_moves_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_moves_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_moves_hint)
	_filter()
	_refresh_slots()


## The member as chosen: DEFAULT_MEMBER's keys.
func member() -> Dictionary:
	return _member.duplicate()


## Shows `chosen` (DEFAULT_MEMBER's keys); a species that isn't in the roster leaves the list's
## first one picked.
func set_member(chosen: Dictionary) -> void:
	_member = DEFAULT_MEMBER.duplicate()
	_member.merge(chosen, true)
	_search.text = ""
	_filter()
	var index := _species.find_custom(func(entry: Array) -> bool: return entry[1] == _member.species)
	_select_species(index if index >= 0 else 0, false)
	_moves.text = _member.moves
	_choose(_ai, _member.ai)
	_choose(_shiny, _member.shiny)
	_choose(_form, _member.form)
	_choose(_ability, _member.ability)
	_choose(_item, _member.item)
	_slot = 0
	_refresh_slots()


## The bench's species IDs, in team order.
func bench() -> Array[String]:
	var ids: Array[String] = []
	for id in str(_member.bench).split(",", false):
		ids.append(id)
	return ids


## Picks team slot `index` for the species list: the first member (the details edit it) or a
## bench member, the next empty slot included.
func _pick_slot(index: int) -> void:
	_slot = mini(index, bench().size() + 1)
	_refresh_slots()
	_show_slot_species()


func _remove_slot() -> void:
	var ids := bench()
	if _slot == 0 or _slot > ids.size():
		return
	ids.remove_at(_slot - 1)
	_member.bench = ",".join(ids)
	_slot = mini(_slot, ids.size())
	_refresh_slots()
	_show_slot_species()
	changed.emit()


## The slot buttons: each member's name, "+" on the next empty slot (while the team has room),
## the picked one pressed; the details only for the first member.
func _refresh_slots() -> void:
	var ids := bench()
	for i in _slot_buttons.size():
		var button := _slot_buttons[i]
		var id: String = _member.species if i == 0 else (ids[i - 1] if i - 1 < ids.size() else "")
		button.visible = i <= ids.size() + 1
		button.text = "%d %s" % [i + 1, _data.species.get(id, {}).get("name", id)] if not id.is_empty() else "%d +" % (i + 1)
		button.set_pressed_no_signal(i == _slot)
	_grid.visible = _slot == 0
	_bench_hint.visible = _slot > 0


## The name, types and preview for the picked slot's species, and its entry selected in the list.
func _show_slot_species() -> void:
	var ids := bench()
	var id: String = _member.species if _slot == 0 or _slot > ids.size() else ids[_slot - 1]
	if _slot == 0:
		var index := _species.find_custom(func(entry: Array) -> bool: return entry[1] == id)
		if index >= 0:
			_select_species(index, false)
		return
	_name.text = str(_data.species.get(id, {}).get("name", "Pick a species")) if not id.is_empty() else "Pick a species"
	for child in _types.get_children():
		child.queue_free()
	for type: String in _data.species.get(id, {}).get("types", []):
		_types.add_child(_pill(type))
	_preview_wait = PREVIEW_DELAY


## Whether a player controls this side (play mode), which leaves it without an AI.
func set_player(player: bool) -> void:
	_player = player
	_ai.disabled = player
	if player:
		_ai.text = "You"
	else:
		_choose(_ai, _member.ai)


func focus_search() -> void:
	_search.grab_focus()


func _process(delta: float) -> void:
	if _preview_wait < 0.0:
		return
	_preview_wait -= delta
	if _preview_wait < 0.0:
		_show_preview()


## Lists the species whose name or ID holds the search text, keeping the current one selected.
func _filter() -> void:
	var query := _search.text.strip_edges().to_lower()
	var id_query := BattleData.to_id(query)
	_list.clear()
	for entry: Array in _species:
		if query.is_empty() or entry[0].to_lower().contains(query) or (not id_query.is_empty() and entry[1].contains(id_query)):
			var index := _list.add_item(entry[0])
			_list.set_item_metadata(index, entry[1])
			if entry[1] == _member.species:
				_list.select(index)
	# The list scrolls once it has been laid out.
	_list.ensure_current_is_visible.call_deferred()


func _pick_first() -> void:
	if _list.item_count > 0:
		_list.select(0)
		_on_species_selected(0)
		_list.grab_focus()


func _on_search_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_DOWN and _list.item_count > 0:
		_list.grab_focus()
		if _list.get_selected_items().is_empty():
			_list.select(0)
			_on_species_selected(0)
		accept_event()


func _on_species_selected(index: int) -> void:
	var id: String = _list.get_item_metadata(index)
	if _slot > 0:
		var ids := bench()
		if _slot > ids.size():
			ids.append(id)
			_slot = ids.size()
		else:
			ids[_slot - 1] = id
		_member.bench = ",".join(ids)
		_refresh_slots()
		_show_slot_species()
		changed.emit()
		return
	if id == _member.species:
		return
	_select_species(_species.find_custom(func(entry: Array) -> bool: return entry[1] == id), true)


## Makes `_species[index]` the member's species: its name, types, forms and standard ability,
## item and moves. With `reset`, choices that belong to the old species go back to defaults.
func _select_species(index: int, reset: bool) -> void:
	if index < 0 or index >= _species.size():
		return
	var id: String = _species[index][1]
	_member.species = id
	if reset:
		for key: String in ["form", "ability", "item", "moves"]:
			_member[key] = ""
		_moves.text = ""
	var species: Dictionary = _data.species[id]
	_name.text = _species[index][0]
	for child in _types.get_children():
		child.queue_free()
	for type: String in species.get("types", []):
		_types.add_child(_pill(type))

	_form.clear()
	_add(_form, ROLLED, "")
	_add(_form, "Own look", Appearance.BASE_FORM)
	var forms: Array = _data.roster.get(id, {}).get("forms", {}).keys()
	forms.sort()
	for form: String in forms:
		_add(_form, form.capitalize(), form)
	_choose(_form, _member.form)

	var moveset := _data.standard_moveset(id)
	var standard_moves: Array = moveset.get("moves", [])
	var standard_ability := _data.standard_ability(id)
	var standard_item := ""
	var moves: Array[BattleMove] = []
	for move_id: String in standard_moves:
		var converted := _data.convert_move(move_id)
		if converted.has("move"):
			moves.append(converted.move)
	standard_item = Items.standard(species, moves, _data, standard_ability)
	_ability.clear()
	_add(_ability, "Standard (%s)" % _named(Abilities.display_name(standard_ability), standard_ability), "")
	_add(_ability, "None", SpecFlags.NONE)
	for ability in _sorted_by_name(Abilities.table(), Abilities.display_name):
		_add(_ability, Abilities.display_name(ability), ability)
	_choose(_ability, _member.ability)
	_item.clear()
	_add(_item, "Standard (%s)" % _named(Items.display_name(standard_item), standard_item), "")
	_add(_item, "None", SpecFlags.NONE)
	for item in _sorted_by_name(Items.table(), Items.display_name):
		_add(_item, Items.display_name(item), item)
	_choose(_item, _member.item)
	var names := moves.map(func(move: BattleMove) -> String: return move.name)
	_moves.placeholder_text = "Standard: " + ", ".join(names) if not names.is_empty() else "Standard"
	_moves_hint.text = "Comma-separated names, e.g. %s" % ", ".join(names.slice(0, 2)) if not names.is_empty() \
		else str(moveset.get("error", ""))
	_preview_wait = PREVIEW_DELAY
	if not _slot_buttons.is_empty():
		_refresh_slots()
	changed.emit()


func _show_preview() -> void:
	var ids := bench()
	if _slot > 0:
		var entry: Dictionary = _data.roster.get(ids[_slot - 1] if _slot <= ids.size() else "", {})
		if not entry.is_empty():
			_preview.show_model(entry, Appearance.resolve(entry, {}, BattleView.MODELS_DIR))
		return
	var entry: Dictionary = _data.roster.get(_member.species, {})
	if entry.is_empty():
		return
	var form: String = _member.form if _member.form != Appearance.BASE_FORM else ""
	_preview.show_model(entry, Appearance.resolve(entry, {"form": form, "shiny": _member.shiny == "yes"}, BattleView.MODELS_DIR))


func _change(key: String, value: String) -> void:
	if _member[key] == value:
		return
	_member[key] = value
	if key in ["form", "shiny"]:
		_preview_wait = PREVIEW_DELAY
	changed.emit()


func _option(grid: GridContainer, caption: String) -> OptionButton:
	grid.add_child(_caption(caption))
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.fit_to_longest_item = false
	option.clip_text = true
	var key := caption.to_lower()
	option.item_selected.connect(func(index: int) -> void: _change(key, str(option.get_item_metadata(index))))
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


## Selects the item whose value is `value`, or the first (the default).
func _choose(option: OptionButton, value: String) -> void:
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			return
	option.select(0)


func _pill(type: String) -> Label:
	var pill := Label.new()
	pill.text = type.to_upper()
	pill.add_theme_font_size_override("font_size", 20)
	pill.add_theme_color_override("font_outline_color", TypeColors.of(type).darkened(0.5))
	pill.add_theme_constant_override("outline_size", 5)
	var style := StyleBoxFlat.new()
	style.bg_color = TypeColors.of(type)
	style.set_corner_radius_all(12)
	style.content_margin_left = 10
	style.content_margin_right = 10
	pill.add_theme_stylebox_override("normal", style)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return pill


static func _named(name: String, id: String) -> String:
	return name if not id.is_empty() else "none"


static func _sorted_by_name(table: Dictionary, display_name: Callable) -> Array:
	var ids := table.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return str(display_name.call(a)).naturalnocasecmp_to(display_name.call(b)) < 0)
	return ids
