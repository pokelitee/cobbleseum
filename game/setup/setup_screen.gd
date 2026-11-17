class_name SetupScreen
extends Control
## The setup screen (concepts_brief.md §17, M13), where a plain launch starts: the mode (watch,
## play, record), each side's fighter (SetupSide), the arena, weather and seed, and for record
## the clip's format and length. It builds battle flags (flags_for()) and SpecFlags turns them
## into the spec, exactly as on the command line; the command line it stands for shows at the
## bottom. Watch and play open the battle view with those flags; record runs tools/record.gd in
## the background. A launch with arguments goes straight to the battle view, as before.
##
## Keys: Tab moves between controls, Enter in a species search picks the first match, F5 or
## Ctrl+Enter starts, Esc quits.

const SCENE := "res://game/setup/setup_screen.tscn"
const VIEW_SCENE := "res://game/presentation/battle_view.tscn"
const RECORD_SCRIPT := "res://tools/record.gd"
const MODES: Array[String] = ["watch", "play", "record"]
const MODE_HINTS := {
	"watch": "Two AIs fight, with the planned camera, slow motion and replay.",
	"play": "You control side A against the AI.",
	"record": "Renders clips to recordings/ (needs ffmpeg; a few minutes).",
}
const WEATHER_CHOICES := {"": "Arena's own", "none": "None", "rain": "Rain", "sun": "Sun", "sand": "Sand", "snow": "Snow"}
const FORMATS: Array[String] = ["vertical", "landscape", "both"]
const DEFAULT_FOE := "blastoise"
const DEFAULT_SPECIES := "garchomp"
const MARGIN := 40

## Whether the command line's arguments have been handed to the battle view, which happens
## only once: coming back to the menu shows the menu.
static var _arguments_used := false
## The last setup started, shown again when a battle returns to the menu.
static var _last := {}

var _data: BattleData
var _mode := "watch"
var _sides: Array[SetupSide] = []
var _mode_buttons := {}
var _mode_hint: Label
var _arena: OptionButton
var _weather: OptionButton
var _seed: LineEdit
var _record_options: Control
var _format: OptionButton
var _seconds: SpinBox
var _status: Label
var _command: Label
var _start: Button
var _open_folder: Button
var _recording: Thread
var _recorded_dir := ""


## The battle flags (SpecFlags) for a setup: {"mode", "sides": [SetupSide.member() for A, B],
## "arena", "weather", "seed", ...}, each "" for its default.
static func flags_for(setup: Dictionary) -> Dictionary:
	var sides: Array = setup.sides
	var playing: bool = setup.mode == "play"
	var flags := {("play" if playing else "watch"): sides[0].species, "vs": sides[1].species}
	flags.ai = sides[1].ai if playing else sides[0].ai
	if not playing:
		flags["vs-ai"] = sides[1].ai
	for key: String in ["seed", "arena", "weather"]:
		if not str(setup.get(key, "")).is_empty():
			flags[key] = str(setup[key])
	if sides.any(func(member: Dictionary) -> bool: return not str(member.get("shiny", "")).is_empty()):
		# A side left to the seed shows as not shiny once the other is set: --shiny names both.
		flags.shiny = SpecFlags.SHINY_SIDES.find_key(sides.map(func(member: Dictionary) -> bool: return member.get("shiny", "") == "yes"))
	for side in 2:
		var prefix: String = ["", "vs-"][side]
		for key: String in ["form", "moves", "ability", "item"]:
			if not str(sides[side].get(key, "")).is_empty():
				flags[prefix + key] = str(sides[side][key])
	return flags


## Why the flags can't start a battle with `data`, or "": the same checks as the command line.
static func problem_for(flags: Dictionary, data: BattleData) -> String:
	var spec := SpecFlags.to_spec(flags)
	if spec.has("error"):
		return spec.error
	var problem := Cli.check_spec(spec, data)
	return problem if not problem.is_empty() else Appearance.check(spec, data.roster)


## The command line that runs the same battle: the game's, or tools/record.gd's with `record`.
static func command_line(args: PackedStringArray, record: bool) -> String:
	var quoted: PackedStringArray = []
	for arg in args:
		quoted.append("\"%s\"" % arg if arg.contains(" ") else arg)
	if record:
		return "godot --headless --path . --script %s -- %s" % [RECORD_SCRIPT, " ".join(quoted)]
	return "godot --path . -- " + " ".join(quoted)


func _ready() -> void:
	UiFonts.use_by_default()
	if not _arguments_used:
		_arguments_used = true
		if not OS.get_cmdline_user_args().is_empty():
			get_tree().change_scene_to_file.call_deferred(VIEW_SCENE)
			return
	theme = MenuTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuTheme.background())
	var loaded := BattleData.load_all()
	if loaded.has("error"):
		_show_error(loaded.error)
		return
	_data = loaded.data
	_build()
	_restore(_last if not _last.is_empty() else {"mode": "watch",
		"sides": [{"species": DEFAULT_SPECIES}, {"species": DEFAULT_FOE}]})
	_sides[0].focus_search()


func _build() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		root.set("offset_" + side, MARGIN if side in ["left", "top"] else -MARGIN)
	root.add_theme_constant_override("separation", 20)
	add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	root.add_child(header)
	header.add_child(MenuTheme.title("COBBLESEUM", 72, Hud.GOLD))
	_mode_hint = Label.new()
	_mode_hint.add_theme_color_override("font_color", MenuTheme.MUTED)
	_mode_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mode_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(_mode_hint)
	var group := ButtonGroup.new()
	for mode in MODES:
		var button := Button.new()
		button.text = mode.capitalize()
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(150, 64)
		button.add_theme_font_override("font", UiFonts.DISPLAY)
		button.add_theme_font_size_override("font_size", 32)
		button.toggled.connect(func(on: bool) -> void:
			if on:
				_set_mode(mode))
		header.add_child(button)
		_mode_buttons[mode] = button

	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 16)
	sides.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(sides)
	for side in 2:
		var panel := SetupSide.new(side, _data)
		panel.changed.connect(_on_side_changed.bind(side))
		_sides.append(panel)
		sides.add_child(panel)
		if side == 0:
			var vs := MenuTheme.title("VS", 72, Hud.GOLD)
			vs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sides.add_child(vs)

	var footer := PanelContainer.new()
	footer.add_theme_stylebox_override("panel", MenuTheme.plate())
	root.add_child(footer)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	footer.add_child(rows)
	var battle_row := HBoxContainer.new()
	battle_row.add_theme_constant_override("separation", 14)
	rows.add_child(battle_row)
	_arena = _option(battle_row, "Arena", 250)
	_add(_arena, "By type (seed)", "")
	for name in Arenas.names():
		_add(_arena, str(Arenas.preset(name).get("name", name)), name)
	_weather = _option(battle_row, "Weather", 180)
	for key: String in WEATHER_CHOICES:
		_add(_weather, WEATHER_CHOICES[key], key)
	battle_row.add_child(_caption("Seed"))
	_seed = LineEdit.new()
	_seed.placeholder_text = "Random"
	_seed.custom_minimum_size.x = 200
	_seed.text_changed.connect(func(_text: String) -> void: _refresh())
	_seed.text_submitted.connect(func(_text: String) -> void: _on_start())
	battle_row.add_child(_seed)
	var dice := Button.new()
	dice.text = "Roll"
	dice.tooltip_text = "Fill in a random seed, to repeat this battle later"
	dice.pressed.connect(func() -> void:
		_seed.text = str(randi() % 1000000)
		_refresh())
	battle_row.add_child(dice)
	var record_row := HBoxContainer.new()
	record_row.add_theme_constant_override("separation", 14)
	battle_row.add_child(record_row)
	_record_options = record_row
	_format = _option(record_row, "Format", 170)
	for format in FORMATS:
		_add(_format, format.capitalize(), format)
	record_row.add_child(_caption("Seconds"))
	_seconds = SpinBox.new()
	_seconds.min_value = 1
	_seconds.max_value = 60
	_seconds.value = 10
	_seconds.custom_minimum_size.x = 120
	_seconds.value_changed.connect(func(_value: float) -> void: _refresh())
	record_row.add_child(_seconds)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 14)
	rows.add_child(action_row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	action_row.add_child(text)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(_status)
	_command = Label.new()
	_command.add_theme_font_size_override("font_size", 18)
	_command.add_theme_color_override("font_color", MenuTheme.MUTED)
	_command.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(_command)
	_open_folder = Button.new()
	_open_folder.text = "Open folder"
	_open_folder.visible = false
	_open_folder.pressed.connect(func() -> void: OS.shell_open(_recorded_dir))
	action_row.add_child(_open_folder)
	var quit := Button.new()
	quit.text = "Quit"
	quit.custom_minimum_size.x = 130
	quit.pressed.connect(func() -> void: get_tree().quit())
	action_row.add_child(quit)
	_start = Button.new()
	_start.custom_minimum_size = Vector2(240, 72)
	_start.add_theme_font_override("font", UiFonts.DISPLAY)
	_start.add_theme_font_size_override("font_size", 36)
	_start.add_theme_stylebox_override("normal", _start_style(Hud.GOLD.darkened(0.15)))
	_start.add_theme_stylebox_override("hover", _start_style(Hud.GOLD))
	_start.add_theme_stylebox_override("pressed", _start_style(Hud.GOLD.darkened(0.3)))
	_start.add_theme_stylebox_override("disabled", _start_style(MenuTheme.BUTTON.darkened(0.3)))
	_start.add_theme_color_override("font_color", Color(0.1, 0.08, 0.02))
	_start.add_theme_color_override("font_hover_color", Color(0.1, 0.08, 0.02))
	_start.add_theme_color_override("font_focus_color", Color(0.1, 0.08, 0.02))
	_start.tooltip_text = "F5 or Ctrl+Enter"
	_start.pressed.connect(_on_start)
	action_row.add_child(_start)
	for option: OptionButton in [_arena, _weather, _format]:
		option.item_selected.connect(func(_index: int) -> void: _refresh())


## The setup as chosen (see flags_for()), with the record options.
func _setup() -> Dictionary:
	return {"mode": _mode, "sides": _sides.map(func(side: SetupSide) -> Dictionary: return side.member()),
		"arena": _value(_arena), "weather": _value(_weather), "seed": _seed.text.strip_edges(),
		"format": _value(_format), "seconds": int(_seconds.value)}


func _restore(setup: Dictionary) -> void:
	for side in 2:
		_sides[side].set_member(setup.sides[side])
	_choose(_arena, str(setup.get("arena", "")))
	_choose(_weather, str(setup.get("weather", "")))
	_choose(_format, str(setup.get("format", "vertical")))
	_seed.text = str(setup.get("seed", ""))
	_seconds.value = int(setup.get("seconds", 10))
	_mode_buttons[setup.get("mode", "watch")].button_pressed = true
	_set_mode(setup.get("mode", "watch"))


func _set_mode(mode: String) -> void:
	_mode = mode
	_mode_hint.text = MODE_HINTS[mode]
	_sides[0].set_player(mode == "play")
	_record_options.visible = mode == "record"
	_start.text = {"watch": "Watch", "play": "Fight!", "record": "Record"}[mode]
	_refresh()


## Keeps the two shiny choices consistent: once one side is set, the other can't stay rolled
## (the flags set both, see flags_for()).
func _on_side_changed(side: int) -> void:
	var members := _sides.map(func(panel: SetupSide) -> Dictionary: return panel.member())
	if not str(members[side].shiny).is_empty() and str(members[1 - side].shiny).is_empty():
		members[1 - side].shiny = "no"
		_sides[1 - side].set_member(members[1 - side])
	elif str(members[side].shiny).is_empty() and not str(members[1 - side].shiny).is_empty():
		members[1 - side].shiny = ""
		_sides[1 - side].set_member(members[1 - side])
	_refresh()


## Checks the setup and shows the command line it stands for.
func _refresh() -> void:
	if _sides.size() < 2 or _start == null:
		return
	var setup := _setup()
	var flags := flags_for(setup)
	var problem := problem_for(flags, _data)
	if _recording != null:
		return
	_status.text = problem if not problem.is_empty() else ""
	_status.add_theme_color_override("font_color", Hud.DANGER if not problem.is_empty() else Color.WHITE)
	_start.disabled = not problem.is_empty()
	_command.text = command_line(_arguments(setup), _mode == "record")


## The command-line arguments for the setup: its battle flags, and the record options.
func _arguments(setup: Dictionary) -> PackedStringArray:
	var args := SpecFlags.to_args(flags_for(setup))
	if setup.mode == "record":
		args.append_array(["--format=%s" % setup.format, "--seconds=%d" % setup.seconds])
	return args


func _on_start() -> void:
	if _start.disabled or _recording != null:
		return
	var setup := _setup()
	_last = setup
	if _mode == "record":
		_start_recording(_arguments(setup))
		return
	BattleView.launch_args = _arguments(setup)
	get_tree().change_scene_to_file(VIEW_SCENE)


func _start_recording(args: PackedStringArray) -> void:
	_recording = Thread.new()
	_recording.start(_record.bind(args))
	_start.disabled = true
	_open_folder.visible = false
	_status.remove_theme_color_override("font_color")
	_status.text = "Recording… a render window opens for each format; this takes a few minutes."


## Runs tools/record.gd in its own process (on the recording thread).
static func _record(args: PackedStringArray) -> Dictionary:
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", RECORD_SCRIPT, "--"] + Array(args), output, true)
	return {"code": code, "log": "".join(output)}


func _process(_delta: float) -> void:
	if _recording == null or _recording.is_alive():
		return
	var result: Dictionary = _recording.wait_to_finish()
	_recording = null
	_refresh()
	var log: String = result.log
	for line in log.split("\n"):
		if line.begins_with("wrote "):
			_recorded_dir = line.trim_prefix("wrote ").strip_edges()
	if result.code == 0:
		_status.text = "Saved to %s" % _recorded_dir
		_open_folder.visible = not _recorded_dir.is_empty()
	else:
		var errors := Array(log.strip_edges().split("\n")).filter(func(line: String) -> bool: return line.begins_with("error:"))
		_status.text = "Recording failed: " + (errors.back().trim_prefix("error: ") if not errors.is_empty() else log.strip_edges().right(300))
		_status.add_theme_color_override("font_color", Hud.DANGER)
		printerr(log)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey
	if key.keycode == KEY_F5 or (key.keycode in [KEY_ENTER, KEY_KP_ENTER] and key.ctrl_pressed):
		_on_start()
		accept_event()
	elif key.keycode == KEY_ESCAPE and _recording == null:
		get_tree().quit()


func _exit_tree() -> void:
	if _recording != null:
		_recording.wait_to_finish()


## The screen when the battle data can't load: the reason and how to fix it.
func _show_error(message: String) -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 20)
	add_child(box)
	box.add_child(MenuTheme.title("COBBLESEUM", 72, Hud.GOLD))
	var label := Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 1200
	box.add_child(label)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func() -> void: get_tree().quit(1))
	box.add_child(quit)
	box.position -= box.get_combined_minimum_size() * 0.5
	quit.grab_focus()
	printerr("error: " + message)


func _option(row: HBoxContainer, caption: String, width: float) -> OptionButton:
	row.add_child(_caption(caption))
	var option := OptionButton.new()
	option.custom_minimum_size.x = width
	option.clip_text = true
	row.add_child(option)
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


static func _value(option: OptionButton) -> String:
	return str(option.get_item_metadata(option.selected)) if option.selected >= 0 else ""


static func _start_style(colour: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(16)
	box.content_margin_left = 20
	box.content_margin_right = 20
	return box
