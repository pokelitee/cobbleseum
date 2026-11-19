class_name TournamentCard
extends Control
## A tournament's cards (concepts_brief.md §17, M19), laid out for either clip format:
## - the bracket card before each match: every entrant's portrait and seed in the bracket,
##   results so far (losers dimmed, winners' paths in gold, a series' games won), the last
##   match's winner moving up into its new slot, and the coming match's pair lit, with its round
##   and names in the title;
## - the champion card at the end: the champion's portrait, name and path through the bracket,
##   confetti and the victory sting, then the credits.
## In landscape the bracket's halves come in from the left and right to the champion's slot in
## the middle; in portrait from the top and bottom.
##
## In the window it shows TournamentRun's current step and moves on when done (Space or Enter
## skip, Esc goes back to the menu). Rendered by tools/tournament.gd under Movie Maker, it reads
## user arguments --tournament-file=<tournament.json> --card=<match index>|champion
## [--move-effects] [--trainers] (for the credits) and quits when done.

const SCENE := "res://game/tournament/tournament_card.tscn"
const BRACKET_FRAMES := 150
const CHAMPION_FRAMES := 210
## The champion card's credits come on top of CHAMPION_FRAMES.
const CREDITS_FRAMES := Hud.CREDITS_FRAMES
const FADE_FRAMES := 8
## The last match's winner moves up into its new slot over these frames.
const ADVANCE_START := 14
const ADVANCE_FRAMES := 16
## The coming match's pair pulses with this period.
const PULSE_FRAMES := 36
const LOST_ALPHA := 0.36
const LINE := Color(0.55, 0.6, 0.75, 0.55)
const EMPTY := Color(1, 1, 1, 0.1)
const TILE := Color(0.16, 0.2, 0.32)
const CHAMPION_PORTRAIT := 640
const CONFETTI := 90
## The sting comes this many frames in, after the card has slid in.
const STING_DELAY := 6
## A seed for the confetti, which only needs to fall the same way every render.
const CONFETTI_SEED := 7

var _tournament := {}
## The bracket card's match (about to be played), or -1 for the champion card.
var _match := -1
var _frame := 0
var _frames := BRACKET_FRAMES
var _size := Vector2.ZERO
var _portrait := false
var _scale := 1.0
var _recording := false
var _move_effects := false
var _trainers := false
## Each entrant's lead's portrait (null without a model).
var _textures := {}
var _root: Control
var _lines: Control
## The connectors: [{"points": PackedVector2Array, "gold": bool, "fresh": bool}].
var _connectors: Array[Dictionary] = []
var _pulsing: Array[Control] = []
var _advancing: Control
var _music: BattleMusic
var _credits: Control
var _confetti: Array[Dictionary] = []
var _confetti_layer: Control
var _after: AfterBattle
## Showdown's species, for the champion's team's names.
var _species := {}


## Where each slot of a `size` bracket sits in `area`: {Vector2i(round, j): Rect2}, round 0 the
## entrants by bracket position, round rounds() the champion's slot in the middle. The halves
## (first and second half of each round's slots) come in from the left and right, or from the
## top and bottom in `portrait`; each slot sits between the two it's fed by.
static func layout(size: int, portrait: bool, area: Rect2) -> Dictionary:
	var rounds := Tournament.rounds(size)
	var lanes := 2 * rounds + 1
	var lane := (area.size.y if portrait else area.size.x) / lanes
	var span := area.size.x if portrait else area.size.y
	var pitch := span / (size / 2)
	var along := lane * 0.86
	var across := pitch * 0.86
	var box := Vector2(across, minf(along, across * 0.72)) if portrait else Vector2(along, minf(across, along * 0.45))
	var rects := {}
	for round in rounds + 1:
		var count := size >> round
		for j in count:
			var lane_index := rounds
			var middle := span * 0.5
			if round < rounds:
				var per_half := count / 2
				lane_index = lanes - 1 - round if j >= per_half else round
				middle = ((j % per_half) + 0.5) * pitch * (1 << round)
			var centre_along := (lane_index + 0.5) * lane
			var centre := area.position + (Vector2(middle, centre_along) if portrait else Vector2(centre_along, middle))
			rects[Vector2i(round, j)] = Rect2(centre - box * 0.5, box)
	return rects


## Who's in slot (round, j) once `matches` are decided: an entrant index, or -1 while the match
## feeding it is still to come.
static func occupant(tournament: Dictionary, matches: Array, round: int, j: int) -> int:
	if round == 0:
		return Tournament.bracket_order(tournament.options.size)[j] - 1
	return Tournament.winner_of(tournament, matches, round - 1, j)


func _ready() -> void:
	UiFonts.use_by_default()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_recording = Array(OS.get_cmdline_args()).any(func(a: String) -> bool: return a.begins_with("--write-movie"))
	var source := _source()
	if source.has("error"):
		printerr("error: " + source.error)
		get_tree().quit(1)
		return
	_tournament = source.tournament
	_match = source.match
	_move_effects = source.move_effects
	_trainers = source.trainers
	_size = get_viewport().get_visible_rect().size
	_portrait = VideoFormat.is_portrait(_size)
	_scale = minf(_size.x, _size.y) / Hud.REFERENCE_SIZE
	add_child(MenuTheme.background())
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.modulate.a = 0.0
	add_child(_root)
	var loaded := BattleData.load_all()
	var roster: Dictionary = loaded.data.roster if not loaded.has("error") else {}
	if not loaded.has("error"):
		_species = loaded.data.species
	if _match >= 0:
		_make_portraits(roster, range(_tournament.entrants.size()), FighterPortrait.SIZE)
		_build_bracket()
	else:
		_frames = CHAMPION_FRAMES + CREDITS_FRAMES
		_make_portraits(roster, [_tournament.champion], CHAMPION_PORTRAIT)
		_build_champion()


## What to show: TournamentRun's step in the window, else the user arguments.
func _source() -> Dictionary:
	if TournamentRun.active():
		var step := TournamentRun.current()
		var tournament := TournamentRun.tournament
		return {"tournament": tournament, "match": int(step.get("card", -1)), "move_effects": CobblemonMoveFX.available(),
			"trainers": tournament.entrants.any(func(e: Dictionary) -> bool: return e.has("trainer"))}
	var path := ""
	var card := ""
	var flags := {"move_effects": false, "trainers": false}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tournament-file="):
			path = arg.get_slice("=", 1)
		elif arg.begins_with("--card="):
			card = arg.get_slice("=", 1)
		elif arg in ["--move-effects", "--trainers"]:
			flags[arg.trim_prefix("--").replace("-", "_")] = true
	var tournament := Tournament.from_json(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	if not tournament.has("champion"):
		return {"error": "a card needs --tournament-file=<a played tournament.json> (tools/tournament.gd writes one)"}
	var match := -1 if card == "champion" else (card.to_int() if card.is_valid_int() else -2)
	if match < -1 or match >= tournament.matches.size():
		return {"error": "--card must be a match from 0 to %d, or champion" % (tournament.matches.size() - 1)}
	return {"tournament": tournament, "match": match, "move_effects": flags.move_effects, "trainers": flags.trainers}


func _make_portraits(roster: Dictionary, entrants: Array, pixels: int) -> void:
	for index: int in entrants:
		var lead: Dictionary = _tournament.entrants[index].members[0]
		var entry: Dictionary = roster.get(lead.species, {})
		var portrait: FighterPortrait = null
		if not entry.is_empty():
			var look := Appearance.resolve(entry, lead, BattleView.MODELS_DIR)
			portrait = FighterPortrait.create(BattleView.MODELS_DIR.path_join(look.model), entry.scale, entry.height,
				BattleView.skin_path(look))
		if portrait != null:
			portrait.size = Vector2i(pixels, pixels)
			add_child(portrait)
		_textures[index] = portrait.get_texture() if portrait != null else null


func _build_bracket() -> void:
	var options: Dictionary = _tournament.options
	var entrants: int = options.size
	var rounds := Tournament.rounds(entrants)
	var decided: Array = _tournament.matches.slice(0, _match)
	var coming: Dictionary = _tournament.matches[_match]
	var margin := 40.0 * _scale
	var top := (_header(coming) + 24.0) * _scale
	var bottom := _footer()
	var area := Rect2(Vector2(margin, top), Vector2(_size.x - 2 * margin, _size.y - top - bottom))
	var rects := layout(entrants, _portrait, area)
	_lines = Control.new()
	_lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.draw.connect(_draw_lines)
	_root.add_child(_lines)
	var last: Dictionary = decided.back() if not decided.is_empty() else {}
	for key: Vector2i in rects:
		var who := occupant(_tournament, decided, key.x, key.y) if key.x < rounds else -1
		var feeds := Tournament.winner_of(_tournament, decided, key.x, key.y / 2) if key.x < rounds else -1
		var lost := feeds >= 0 and feeds != who
		var slot := _slot(rects[key], who, key.x == rounds, lost, _wins(decided, key, who))
		_root.add_child(slot)
		if key.x == coming.round and key.y / 2 == coming.index:
			_pulsing.append(slot)
		var fresh := not last.is_empty() and key == Vector2i(last.round + 1, last.index)
		if fresh:
			_advancing = slot
		if key.x < rounds:
			var parent: Rect2 = rects[Vector2i(key.x + 1, key.y / 2)]
			_connectors.append({"points": _connector(rects[key], parent, key, entrants), "gold": feeds >= 0 and feeds == who,
				"fresh": not last.is_empty() and key.x == last.round and key.y / 2 == last.index and feeds == who})


## The title band: the cup, the coming match's round and its pair. Returns its height at
## reference scale.
func _header(coming: Dictionary) -> float:
	var options: Dictionary = _tournament.options
	var band := VBoxContainer.new()
	band.alignment = BoxContainer.ALIGNMENT_CENTER
	band.add_theme_constant_override("separation", roundi(-4 * _scale))
	var kicker := _title("COBBLESEUM CUP", 40, Hud.GOLD)
	var title := _title(Tournament.match_title(options.size, coming.round, coming.index).to_upper(), 100, Color.WHITE)
	var pair := HBoxContainer.new()
	pair.alignment = BoxContainer.ALIGNMENT_CENTER
	pair.add_theme_constant_override("separation", roundi(24 * _scale))
	var parts: Array = [[_name_of(coming.entrants[0]), Hud.SIDE_COLOURS[0]], ["vs", Hud.GOLD], [_name_of(coming.entrants[1]), Hud.SIDE_COLOURS[1]]]
	for part: Array in parts:
		var label := _title(part[0], 56, Color.WHITE if part[0] != "vs" else Hud.GOLD)
		if part[0] != "vs":
			label.add_theme_color_override("font_outline_color", (part[1] as Color).darkened(0.35))
		pair.add_child(label)
	_fit_box(pair, _size.x - 80 * _scale)
	for label: Label in [kicker, title]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_fit_width(label, _size.x - 80 * _scale)
	band.add_child(kicker)
	band.add_child(title)
	band.add_child(pair)
	band.size = Vector2(_size.x, band.get_combined_minimum_size().y)
	band.position = Vector2(0, (60 if _portrait else 24) * _scale)
	_root.add_child(band)
	return band.position.y / _scale + band.size.y / _scale


## The line along the bottom: the format, the seeding and the seed. Returns its height in pixels.
func _footer() -> float:
	var options: Dictionary = _tournament.options
	var seeding: Dictionary = _tournament.seeding
	var label := _text("%d entrants · %s · best of %d · seeded by %s · seed %d" % [options.size,
		Tournament.format_name(options), options.best_of,
		"ranking (rules v%d)" % seeding.rules if seeding.source == "ranking" else "base stats", options.seed], 26, MenuTheme.MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fit_width(label, _size.x - 80 * _scale)
	var height := label.get_combined_minimum_size().y
	label.size = Vector2(_size.x, height)
	var bottom := (70.0 if _portrait else 24.0) * _scale
	label.position = Vector2(0, _size.y - bottom - height)
	_root.add_child(label)
	return bottom + height + 20 * _scale


## One bracket slot: the entrant's portrait, seed and name (and games won in a series), an empty
## outline while it's to be decided, or the champion's slot.
func _slot(rect: Rect2, who: int, champion: bool, lost: bool, wins: int) -> Control:
	var slot := Panel.new()
	slot.position = rect.position
	slot.size = rect.size
	slot.pivot_offset = rect.size * 0.5
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(roundi(minf(rect.size.x, rect.size.y) * 0.16))
	style.bg_color = Hud.PLATE if who >= 0 else Color(0, 0, 0, 0.25)
	style.set_border_width_all(roundi(3 * _scale))
	style.border_color = Hud.GOLD if champion else (Color(1, 1, 1, 0.18) if who >= 0 else EMPTY)
	slot.add_theme_stylebox_override("panel", style)
	if who < 0:
		if champion:
			var label := _title("CHAMPION", 30, Hud.GOLD)
			_fit_width(label, rect.size.x * 0.86)
			_centre(slot, label)
		return slot
	var entrant: Dictionary = _tournament.entrants[who]
	var wide := rect.size.x > rect.size.y * 1.6
	var pad := minf(rect.size.x, rect.size.y) * 0.1
	var tile_size := (rect.size.y - 2 * pad) if wide else minf(rect.size.y * 0.58, rect.size.x - 2 * pad)
	var tile := _tile(who, tile_size)
	tile.position = Vector2(pad, pad) if wide else Vector2((rect.size.x - tile_size) * 0.5, pad)
	slot.add_child(tile)
	var seed_badge := _text(str(entrant.seed), maxi(14, roundi(tile_size * 0.24 / _scale)), Hud.GOLD)
	seed_badge.position = tile.position + Vector2(4, 0) * _scale
	slot.add_child(seed_badge)
	var name_size := maxi(12, roundi(minf(rect.size.y * (0.3 if wide else 0.17), 40.0 * _scale) / _scale))
	var name_label := _title(entrant.name, name_size, Color.WHITE)
	var room := rect.size.x - tile_size - 3 * pad if wide else rect.size.x - 2 * pad
	if wins >= 0:
		var score := _title(str(wins), name_size, Hud.GOLD)
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER if wide else VERTICAL_ALIGNMENT_TOP
		score.size = Vector2(rect.size.x - 2 * pad, rect.size.y if wide else tile_size)
		score.position = Vector2(pad, 0.0 if wide else pad)
		slot.add_child(score)
		if wide:
			room -= _text_width(score) + pad
	_fit_width(name_label, room)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if wide:
		name_label.position = Vector2(tile_size + 2 * pad, 0)
		name_label.size = Vector2(room, rect.size.y)
	else:
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.position = Vector2(pad, pad + tile_size)
		name_label.size = Vector2(room, rect.size.y - 1.5 * pad - tile_size)
	slot.add_child(name_label)
	if lost:
		slot.modulate = Color(0.75, 0.75, 0.8, LOST_ALPHA)
	return slot


## A rounded tile with the entrant's portrait, or the name's initial without one.
func _tile(who: int, side: float) -> Control:
	var tile := Panel.new()
	tile.size = Vector2(side, side)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var style := StyleBoxFlat.new()
	style.bg_color = TILE
	style.set_corner_radius_all(roundi(side * 0.18))
	tile.add_theme_stylebox_override("panel", style)
	var texture: Texture2D = _textures.get(who)
	if texture != null:
		var picture := TextureRect.new()
		picture.texture = texture
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.size = tile.size
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(picture)
	else:
		var initial := _title(str(_tournament.entrants[who].members[0].species).left(1).to_upper(), roundi(side * 0.5 / _scale), Color.WHITE)
		_centre(tile, initial)
	return tile


## Games `who` won in the decided match its slot fed, when a match can have several; else -1.
func _wins(decided: Array, key: Vector2i, who: int) -> int:
	if _tournament.options.best_of == 1 or who < 0 or key.x >= Tournament.rounds(_tournament.options.size):
		return -1
	for bout: Dictionary in decided:
		if bout.round == key.x and bout.index == key.y / 2:
			return bout.wins[bout.entrants.find(who)]
	return -1


## The elbow from slot `key`'s inner edge to the outer edge of the slot it feeds.
func _connector(child: Rect2, parent: Rect2, key: Vector2i, entrants: int) -> PackedVector2Array:
	var second := key.y >= (entrants >> key.x) / 2
	var axis := 1 if _portrait else 0
	var start := child.get_center()
	var finish := parent.get_center()
	var toward := -1.0 if second else 1.0
	start[axis] += child.size[axis] * 0.5 * toward
	finish[axis] -= parent.size[axis] * 0.5 * toward
	var bend := (start[axis] + finish[axis]) * 0.5
	var first_bend := start
	first_bend[axis] = bend
	var second_bend := finish
	second_bend[axis] = bend
	return PackedVector2Array([start, first_bend, second_bend, finish])


func _draw_lines() -> void:
	var grow := clampf((_frame - ADVANCE_START) / float(ADVANCE_FRAMES), 0.0, 1.0)
	for line: Dictionary in _connectors:
		if not line.gold:
			_lines.draw_polyline(line.points, LINE, 2.0 * _scale, true)
	for line: Dictionary in _connectors:
		if line.gold:
			var colour := Hud.GOLD
			colour.a = grow if line.fresh else 1.0
			_lines.draw_polyline(line.points, colour, 5.0 * _scale, true)


func _build_champion() -> void:
	var options: Dictionary = _tournament.options
	var champion: Dictionary = _tournament.entrants[_tournament.champion]
	_confetti_layer = Control.new()
	_confetti_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confetti_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confetti_layer.draw.connect(_draw_confetti)
	_root.add_child(_confetti_layer)
	var random := RandomNumberGenerator.new()
	random.seed = CONFETTI_SEED
	var colours: Array[Color] = [Hud.GOLD, Hud.SIDE_COLOURS[0], Hud.SIDE_COLOURS[1], Color.WHITE, Hud.HEALTHY]
	for i in CONFETTI:
		_confetti.append({"x": random.randf() * _size.x, "y": -random.randf() * _size.y, "speed": random.randf_range(4.0, 9.0),
			"sway": random.randf_range(0.03, 0.08), "phase": random.randf() * TAU, "colour": colours[i % colours.size()],
			"size": Vector2(random.randf_range(10, 18), random.randf_range(18, 30)) * _scale})
	# Portrait stacks everything in one column; landscape puts the portrait left of the words.
	var words := VBoxContainer.new()
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", roundi(12 * _scale))
	var width := (_size.x if _portrait else _size.x * 0.56) - 120 * _scale
	var kicker := _title("COBBLESEUM CUP", 44, Color.WHITE)
	var heading := _title("CHAMPION", 150, Hud.GOLD)
	var side := (720.0 if _portrait else 640.0) * _scale
	var frame := Panel.new()
	frame.custom_minimum_size = Vector2(side, side)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_corner_radius_all(roundi(side * 0.12))
	style.set_border_width_all(roundi(8 * _scale))
	style.border_color = Hud.GOLD
	frame.add_theme_stylebox_override("panel", style)
	var tile := _tile(_tournament.champion, side)
	frame.add_child(tile)
	frame.move_child(tile, 0)
	var name_label := _title(champion.name, 120, Color.WHITE)
	name_label.add_theme_color_override("font_outline_color", Hud.GOLD.darkened(0.55))
	name_label.add_theme_constant_override("outline_size", roundi(20 * _scale))
	var lines: Array[Label] = [kicker, heading, name_label]
	if champion.members.size() > 1:
		lines.append(_text(" · ".join(champion.members.map(func(m: Dictionary) -> String: return _species_name(str(m.species)))), 40, Color.WHITE))
	var path := _text("Beat " + "  ·  ".join(_path()), 38, Color(0.88, 0.9, 0.95))
	path.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	path.custom_minimum_size.x = width
	lines.append(path)
	lines.append(_text("Seed %d of %d · %s · best of %d" % [champion.seed, options.size, Tournament.format_name(options), options.best_of],
		30, MenuTheme.MUTED))
	for label: Label in lines:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if label != path:
			_fit_width(label, width)
		words.add_child(label)
	if _portrait:
		words.add_child(frame)
		words.move_child(frame, 2)
	var layout_box: BoxContainer = words
	if not _portrait:
		layout_box = HBoxContainer.new()
		layout_box.alignment = BoxContainer.ALIGNMENT_CENTER
		layout_box.add_theme_constant_override("separation", roundi(60 * _scale))
		layout_box.add_child(frame)
		layout_box.add_child(words)
	layout_box.size = layout_box.get_combined_minimum_size()
	layout_box.position = (_size - layout_box.size) * 0.5
	_root.add_child(layout_box)
	_credits = _credits_card()
	_music = BattleMusic.new()
	add_child(_music)
	_music.setup(SimRandom.stream(int(options.seed), BattleView.MUSIC_STREAM))
	_music.victory(STING_DELAY)


## Who the champion beat, in order, with the series' score when it had several games.
func _path() -> PackedStringArray:
	var beaten: PackedStringArray = []
	for bout: Dictionary in _tournament.matches:
		var at: int = bout.entrants.find(_tournament.champion)
		if at < 0:
			continue
		var other: int = bout.entrants[1 - at]
		var score := "" if bout.games.size() == 1 else " (%d–%d)" % [bout.wins[at], bout.wins[1 - at]]
		beaten.append(_name_of(other) + score)
	return beaten


func _credits_card() -> Control:
	var card := Control.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.85)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(shade)
	var label := _text(Hud.CREDITS_TEXT % Hud.cobblemon_credit(_move_effects) + ("\n" + Hud.TRAINER_CREDIT if _trainers else ""),
		44, Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var margin := 60.0 * _scale
	label.size = Vector2(_size.x - 2 * margin, 0)
	card.add_child(label)
	label.size.y = label.get_combined_minimum_size().y
	label.position = Vector2(margin, (_size.y - label.size.y) * 0.5)
	card.modulate.a = 0.0
	card.visible = false
	add_child(card)
	return card


func _draw_confetti() -> void:
	for piece: Dictionary in _confetti:
		var y: float = piece.y + piece.speed * _frame * _scale
		if y > _size.y or y < -piece.size.y:
			continue
		var x: float = piece.x + sin(_frame * piece.sway + piece.phase) * 40.0 * _scale
		var turn := sin(_frame * piece.sway * 2.0 + piece.phase)
		var extent: Vector2 = piece.size * Vector2(absf(turn) * 0.8 + 0.2, 1.0)
		_confetti_layer.draw_rect(Rect2(Vector2(x, y) - extent * 0.5, extent), piece.colour)


func _process(_delta: float) -> void:
	if _tournament.is_empty() or _after != null:
		return
	_frame += 1
	var shown := _frames if _match >= 0 else CHAMPION_FRAMES
	_root.modulate.a = clampf(minf(_frame / float(FADE_FRAMES), (shown - _frame) / float(FADE_FRAMES)), 0.0, 1.0) \
		if _match >= 0 else clampf(_frame / float(FADE_FRAMES), 0.0, 1.0)
	if _lines != null:
		_lines.queue_redraw()
	if _advancing != null:
		var t := ease(clampf((_frame - ADVANCE_START) / float(ADVANCE_FRAMES), 0.0, 1.0), 0.4)
		_advancing.scale = Vector2.ONE * lerpf(0.6, 1.0, t)
		_advancing.modulate.a = t
	var pulse := 1.0 + 0.04 * (0.5 - 0.5 * cos(TAU * _frame / PULSE_FRAMES))
	for slot in _pulsing:
		slot.scale = Vector2.ONE * pulse
		(slot.get_theme_stylebox("panel") as StyleBoxFlat).border_color = Hud.GOLD
	if _confetti_layer != null:
		_confetti_layer.queue_redraw()
	if _music != null:
		_music.next_frame()
	if _credits != null and _frame >= CHAMPION_FRAMES:
		if not _credits.visible:
			_credits.visible = true
			_music.fade_out(CREDITS_FRAMES)
		_credits.modulate.a = minf(1.0, _credits.modulate.a + 0.1)
	if _frame >= _frames:
		_done()


func _done() -> void:
	if not TournamentRun.active():
		get_tree().quit(0)
	elif _match >= 0:
		TournamentRun.advance(get_tree())
	else:
		# The buttons come over the champion again, not over the credits.
		_credits.visible = false
		_after = AfterBattle.new()
		_after.rematch.connect(func() -> void: TournamentRun.restart(get_tree()))
		_after.menu.connect(_menu)
		add_child(_after)


func _menu() -> void:
	TournamentRun.stop()
	get_tree().change_scene_to_file(SetupScreen.SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if _recording or not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).keycode:
		KEY_ESCAPE:
			_menu()
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			if _after == null:
				_frame = maxi(_frame, _frames - 1)
		KEY_R:
			if _after != null:
				TournamentRun.restart(get_tree())


func _name_of(entrant: int) -> String:
	return str(_tournament.entrants[entrant].name)


func _species_name(id: String) -> String:
	return str(_species.get(id, {}).get("name", id))


func _title(text: String, font_size: int, colour: Color) -> Label:
	var label := MenuTheme.title(text, roundi(font_size * _scale), colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _text(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", roundi(font_size * _scale))
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", roundi(8 * _scale))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _centre(parent: Control, child: Label) -> void:
	child.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	child.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	child.size = parent.size
	parent.add_child(child)


## Shrinks a one-line label's font until its text fits `width`.
static func _fit_width(label: Label, width: float) -> void:
	var text_width := _text_width(label)
	if text_width > width:
		label.add_theme_font_size_override("font_size", floori(label.get_theme_font_size("font_size") * width / text_width))


## A one-line label's text width at its font size, with its outline.
static func _text_width(label: Label) -> float:
	return label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		label.get_theme_font_size("font_size")).x + label.get_theme_constant("outline_size")


## Shrinks every label in a row by the same share until the row fits `width`.
static func _fit_box(row: BoxContainer, width: float) -> void:
	var total := row.get_combined_minimum_size().x
	if total <= width:
		return
	for label: Label in row.get_children():
		label.add_theme_font_size_override("font_size", floori(label.get_theme_font_size("font_size") * width / total))
