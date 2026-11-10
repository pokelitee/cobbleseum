class_name MoveStyle
extends RefCounted
## How a move looks (concepts_brief.md §12.5). Each damaging move gets one visual style,
## drawn by MoveFX in its type colour. The style comes from, in order:
## 1. game/data/move_styles.json, a committed table for moves Showdown's flags don't describe;
## 2. Showdown's flags (punch, bite, slicing, bullet, pulse, sound, wind, powder);
## 3. strike for contact moves, orb for everything else.
## Melee styles apply only to contact moves and ranged styles only to the rest, so a table
## entry that contradicts the move's kind is ignored. Styles are presentation only.

const TABLE_FILE := "res://game/data/move_styles.json"
const MELEE: Array[String] = ["strike", "punch", "kick", "bite", "slash", "rush"]
const RANGED: Array[String] = ["orb", "bullet", "beam", "bolt", "stream", "pulse", "sound", "wind",
	"powder", "skyfall", "erupt", "quake", "mind", "explosion"]
const MELEE_FLAGS := {"punch": "punch", "bite": "bite", "slicing": "slash"}
const RANGED_FLAGS := {"bullet": "bullet", "pulse": "pulse", "sound": "sound", "wind": "wind", "powder": "powder"}

static var _table := {}


## The style of a move from its Showdown data. `table` maps move id -> style; it defaults
## to the committed table.
static func of(id: String, data: Dictionary, table: Dictionary = {}) -> String:
	var lookup := table if not table.is_empty() else committed_table()
	var flags: Dictionary = data.get("flags", {})
	var contact := flags.has("contact")
	var listed: String = lookup.get(id, "")
	if not listed.is_empty() and (MELEE if contact else RANGED).has(listed):
		return listed
	var by_flag := MELEE_FLAGS if contact else RANGED_FLAGS
	for flag: String in by_flag:
		if flags.has(flag):
			return by_flag[flag]
	return "strike" if contact else "orb"


## The committed table as move id -> style, loaded once.
static func committed_table() -> Dictionary:
	if _table.is_empty():
		var parsed := parse_table(FileAccess.get_file_as_string(TABLE_FILE))
		if parsed.has("error"):
			push_error("%s: %s" % [TABLE_FILE, parsed.error])
		_table = parsed.get("table", {})
	return _table


## Parses the table file ({style: [move ids]}, keys starting with "_" ignored).
## Returns {"table": move id -> style} or {"error": String} for an unknown style or a move
## listed twice.
static func parse_table(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {"error": "not a JSON object"}
	var table := {}
	for style: String in parsed:
		if style.begins_with("_"):
			continue
		if not (MELEE.has(style) or RANGED.has(style)):
			return {"error": "unknown style '%s'" % style}
		for id: String in parsed[style]:
			if table.has(id):
				return {"error": "'%s' is listed under both %s and %s" % [id, table[id], style]}
			table[id] = style
	return {"table": table}
