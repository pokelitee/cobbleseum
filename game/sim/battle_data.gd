class_name BattleData
extends RefCounted
## Species, moves and the type chart from Showdown's exported JSON (concepts_brief.md §5.1),
## and the roster built from Cobblemon's models (§8): Showdown ID -> {"model", "scale",
## "height", "radius", ...}. The roster is empty in tests that build data by hand.

const SHOWDOWN_DIR := "res://cache/build/showdown/0.11.11"
const ROSTER_FILE := "res://cache/build/cobblemon/1.8.4/roster.json"
## The asset manifest (§6), whose pinned SHA-256 per source names the data a battle runs on.
const MANIFEST := "res://sources.json"
const SOURCES: Array[String] = ["showdown", "cobblemon"]

var species: Dictionary
var moves: Dictionary
var type_chart: Dictionary
## Showdown ID -> {"learnset": {move id: [sources]}}, for the moveset generator.
var learnsets: Dictionary
var roster: Dictionary = {}
## The data versions (§10): source -> the SHA-256 the manifest pins for it. Empty for data
## built by hand.
var versions: Dictionary = {}
## Converted moves and generated movesets, cached: both depend only on the data.
var _converted := {}
var _movesets := {}
var _effectiveness := {}


func _init(species_table: Dictionary, move_table: Dictionary, type_table: Dictionary, learnset_table: Dictionary = {}) -> void:
	species = species_table
	moves = move_table
	type_chart = type_table
	learnsets = learnset_table


## The move as the rules use it: {"move": BattleMove} or {"error"}, cached. BattleMove
## objects are never changed after conversion, so battles share them.
func convert_move(move_id: String) -> Dictionary:
	if not _converted.has(move_id):
		_converted[move_id] = BattleMove.from_showdown(move_id, moves.get(move_id, {})) if moves.has(move_id) \
			else {"error": "unknown move '%s'" % move_id}
	return _converted[move_id]


## The species' standard moveset (Movesets.generate), cached.
func standard_moveset(species_id: String) -> Dictionary:
	if not _movesets.has(species_id):
		_movesets[species_id] = Movesets.generate(species_id, self)
	return _movesets[species_id]


## A Showdown ID from a name: "Mr. Mime" -> "mrmime".
static func to_id(name: String) -> String:
	var id := ""
	for c in name.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			id += c
	return id


## Loads the Showdown data and the roster, with their versions. Returns {"data": BattleData}
## or {"error": String}.
static func load_all() -> Dictionary:
	var loaded := load_showdown()
	if loaded.has("error"):
		return loaded
	var path := ProjectSettings.globalize_path(ROSTER_FILE)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not (parsed is Dictionary and parsed.get("species") is Dictionary):
		return {"error": "%s is missing or invalid; run the asset pipeline first (tools/assets.gd)" % path}
	loaded.data.roster = parsed.species
	var pinned := manifest_versions()
	if pinned.has("error"):
		return pinned
	loaded.data.versions = pinned.versions
	return loaded


## The data versions the manifest pins: {"versions": {source: SHA-256}} or {"error": String}.
static func manifest_versions(path := MANIFEST) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	var sources: Variant = parsed.get("sources") if parsed is Dictionary else null
	var versions := {}
	for id in SOURCES:
		var source: Variant = sources.get(id) if sources is Dictionary else null
		var sha256: Variant = source.get("sha256") if source is Dictionary else null
		if not sha256 is String:
			return {"error": "%s is missing or has no sha256 for %s" % [path, id]}
		versions[id] = sha256
	return {"versions": versions}


## Loads the exported Showdown data. Returns {"data": BattleData} or {"error": String}.
static func load_showdown(dir := SHOWDOWN_DIR) -> Dictionary:
	var tables := {}
	for name in ["pokedex", "moves", "typechart", "learnsets"]:
		var path := ProjectSettings.globalize_path(dir.path_join(name + ".json"))
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if not parsed is Dictionary:
			return {"error": "%s is missing or invalid; run the asset pipeline first (tools/assets.gd)" % path}
		tables[name] = parsed
	return {"data": BattleData.new(tables.pokedex, tables.moves, tables.typechart, tables.learnsets)}


## Main-series effectiveness of an attacking type against a defender's types (0 to 4).
func effectiveness(attack_type: String, defender_types: Array) -> float:
	# Asked every hit and by the AI every decision, so results are cached per type combination.
	var key := attack_type + ">" + ",".join(defender_types)
	var cached: Variant = _effectiveness.get(key)
	if cached != null:
		return cached
	var total := 1.0
	for defender: String in defender_types:
		var taken: Dictionary = type_chart.get(defender.to_lower(), {}).get("damageTaken", {})
		match int(taken.get(attack_type, 0)):
			1: total *= 2.0
			2: total *= 0.5
			3: total *= 0.0
	_effectiveness[key] = total
	return total
