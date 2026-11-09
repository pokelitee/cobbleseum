class_name BattleData
extends RefCounted
## Species, moves and the type chart from Showdown's exported JSON (concepts_brief.md §5.1).

const SHOWDOWN_DIR := "res://cache/build/showdown/0.11.11"

var species: Dictionary
var moves: Dictionary
var type_chart: Dictionary


func _init(species_table: Dictionary, move_table: Dictionary, type_table: Dictionary) -> void:
	species = species_table
	moves = move_table
	type_chart = type_table


## Loads the exported Showdown data. Returns {"data": BattleData} or {"error": String}.
static func load_showdown(dir := SHOWDOWN_DIR) -> Dictionary:
	var tables := {}
	for name in ["pokedex", "moves", "typechart"]:
		var path := ProjectSettings.globalize_path(dir.path_join(name + ".json"))
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if not parsed is Dictionary:
			return {"error": "%s is missing or invalid; run the asset pipeline first (tools/assets.gd)" % path}
		tables[name] = parsed
	return {"data": BattleData.new(tables.pokedex, tables.moves, tables.typechart)}


## Main-series effectiveness of an attacking type against a defender's types (0 to 4).
func effectiveness(attack_type: String, defender_types: Array) -> float:
	var total := 1.0
	for defender: String in defender_types:
		var taken: Dictionary = type_chart.get(defender.to_lower(), {}).get("damageTaken", {})
		match int(taken.get(attack_type, 0)):
			1: total *= 2.0
			2: total *= 0.5
			3: total *= 0.0
	return total
