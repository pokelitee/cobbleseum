class_name Arenas
extends RefCounted
## The arena presets (concepts_brief.md §12.7): one JSON file per arena in PRESETS_DIR, named
## after the arena. A preset combines
## - a field (Terrain.FIELDS): the ground the battle is fought on, which is the simulation's;
## - a venue: "open" (the field's own landscape all around) or "coliseum" (stands around the
##   field, with an optional "theme" of colours, see Stadium);
## - its look, for the presentation: sky, sun, ambient light, fog and weather particles;
## - how a battle without a requested arena may get it: "always" (any fighters) or "suits"
##   (fighters with one of these types);
## - for a coliseum, an optional "crowd": {"fill": share of seats taken, "watchers": how many
##   Cobblemon watch} (Crowd has the defaults).
## Adding an arena is adding a file; the choice of arena is part of the battle (its terrain).

const PRESETS_DIR := "res://game/data/arenas"
const VENUES: Array[String] = ["open", "coliseum"]
## The most Cobblemon a preset's crowd may seat in the front row.
const MAX_WATCHERS := 8

static var _presets := {}


## Every valid preset by name. Invalid files are reported and left out.
static func all() -> Dictionary:
	if _presets.is_empty():
		_presets = _load()
	return _presets


static func names() -> Array[String]:
	var names: Array[String] = []
	names.assign(all().keys())
	names.sort()
	return names


static func preset(name: String) -> Dictionary:
	return all().get(name, {})


## Whether the arena puts walls and stands around its field rather than open land.
static func enclosed(name: String) -> bool:
	return preset(name).get("venue", "open") != "open"


## The arena for a battle: `requested` if it names a preset, else one picked by `seed` from
## the presets that are always offered or that suit one of the fighters' types.
static func choose(requested: String, types: Array, seed: int) -> String:
	if all().has(requested):
		return requested
	var options: Array[String] = []
	for name in names():
		var entry: Dictionary = all()[name]
		if entry.get("always", false) or types.any(func(type: Variant) -> bool: return type in entry.get("suits", [])):
			options.append(name)
	if options.is_empty():
		options = names()
	return options[posmod(seed, options.size())]


static func _load() -> Dictionary:
	var presets := {}
	var files := DirAccess.get_files_at(PRESETS_DIR)
	for file in files:
		if file.get_extension() != "json":
			continue
		var path := PRESETS_DIR.path_join(file)
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var problem := _problem(parsed)
		if not problem.is_empty():
			push_error("arena preset %s: %s" % [path, problem])
			continue
		presets[file.get_basename()] = parsed
	return presets


static func _problem(entry: Variant) -> String:
	if not entry is Dictionary:
		return "not a JSON object"
	if not Terrain.FIELDS.has(entry.get("field", "")):
		return "unknown field '%s' (one of %s)" % [entry.get("field", ""), Terrain.FIELDS.keys()]
	if not entry.get("venue", "") in VENUES:
		return "unknown venue '%s' (one of %s)" % [entry.get("venue", ""), VENUES]
	for key in ["sky", "sun", "ambient", "fog"]:
		if not entry.has(key):
			return "missing '%s'" % key
	var crowd: Variant = entry.get("crowd", {})
	if not crowd is Dictionary:
		return "'crowd' is not an object"
	var fill: Variant = crowd.get("fill", 0.0)
	if not (fill is float or fill is int) or fill < 0.0 or fill > 1.0:
		return "crowd 'fill' must be a share from 0 to 1"
	var watchers: Variant = crowd.get("watchers", 0)
	if not (watchers is float or watchers is int) or watchers < 0 or watchers > MAX_WATCHERS or watchers != floorf(watchers):
		return "crowd 'watchers' must be a whole number from 0 to %d" % MAX_WATCHERS
	for key: String in crowd:
		if not key in ["fill", "watchers"]:
			return "unknown crowd setting '%s'" % key
	return ""
