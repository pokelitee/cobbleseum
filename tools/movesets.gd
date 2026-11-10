extends SceneTree
## Generates every roster species' standard moveset (concepts_brief.md §9.6) for review.
## Usage: godot --headless --path . --script res://tools/movesets.gd -- [species ...]
## With species IDs, prints their movesets. Without, writes cache/build/movesets.json
## (Showdown ID -> move IDs) and prints a summary: failures, short movesets, the most common
## moves, and agreement with Showdown's Gen 9 random-battle sets, which cover 338 species and
## serve only as a sanity check.

const OUTPUT := "res://cache/build/movesets.json"
const RANDOM_SETS := BattleData.SHOWDOWN_DIR + "/gen9-random-sets.json"
const TOP_MOVES := 15


func _initialize() -> void:
	var loaded := BattleData.load_all()
	if loaded.has("error"):
		printerr("error: " + loaded.error)
		return quit(1)
	var data: BattleData = loaded.data
	var requested := Array(OS.get_cmdline_user_args())
	if not requested.is_empty():
		for id: String in requested:
			var result := Movesets.generate(id, data)
			print("%s: %s" % [id, result.get("error", _names(result.get("moves", []), data))])
		return quit(0)

	var movesets := {}
	var failures := {}
	var short := []
	var counts := {}
	for id: String in data.roster:
		var result := Movesets.generate(id, data)
		if result.has("error"):
			failures[id] = result.error
			continue
		movesets[id] = result.moves
		if result.moves.size() < 4:
			short.append(id)
		for move: String in result.moves:
			counts[move] = counts.get(move, 0) + 1
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(movesets, "  ", false))
	file.close()

	print("%d species, %d failed, %d with fewer than 4 moves" % [data.roster.size(), failures.size(), short.size()])
	for id: String in failures:
		print("  failed %s: %s" % [id, failures[id]])
	if not short.is_empty():
		print("  short: %s" % ", ".join(short.map(func(id: String) -> String: return "%s %s" % [id, movesets[id]])))
	var common := counts.keys()
	common.sort_custom(func(a: String, b: String) -> bool: return counts[a] > counts[b] or (counts[a] == counts[b] and a < b))
	print("most common: %s" % ", ".join(common.slice(0, TOP_MOVES).map(func(m: String) -> String: return "%s %d" % [m, counts[m]])))
	_compare_random_sets(movesets, data)
	print("wrote %s" % ProjectSettings.globalize_path(OUTPUT))
	quit(0)


## Share of our moves that also appear in the species' random-battle movepools.
func _compare_random_sets(movesets: Dictionary, data: BattleData) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path(RANDOM_SETS)))
	if not parsed is Dictionary:
		print("random sets not found; skipping the comparison")
		return
	var compared := 0
	var shared := 0
	var total := 0
	for id: String in movesets:
		if not parsed.has(id):
			continue
		var pool := {}
		for set: Dictionary in parsed[id].get("sets", []):
			for name: String in set.get("movepool", []):
				pool[BattleData.to_id(name)] = true
		compared += 1
		for move: String in movesets[id]:
			total += 1
			if pool.has(move):
				shared += 1
	print("random sets: %d species compared; %d of %d moves (%.0f%%) appear in their movepools" % [
		compared, shared, total, 100.0 * shared / maxi(total, 1)])


static func _names(ids: Array, data: BattleData) -> String:
	return ", ".join(ids.map(func(id: String) -> String: return data.moves[id].name))
