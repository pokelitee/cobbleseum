class_name Cli
extends RefCounted
## The command line's shared help (concepts_brief.md §17, M13): --help and --list, unknown flags
## and misspelt names failing with the nearest matches, and the resolved battle printed at the
## start so any run can be repeated. Used by the game (the setup screen and the battle view),
## tools/record.gd, tools/battle.gd and tools/rank.gd.

const LIST_KINDS: Array[String] = ["species", "arenas", "moves", "abilities", "items", "profiles", "trainers"]
## The controllers a fighter's "ai" may name besides the profiles (Controllers).
const OTHER_AIS: Array[String] = ["stand_in", "player"]
## How many near matches an error suggests.
const SUGGESTIONS := 3

## The battle flags (SpecFlags), shared by the game's, record.gd's and battle.gd's --help.
const SPEC_FLAGS_HELP := """Battle flags (instead of a spec file):
  --watch=<species>        an AI-vs-AI battle with this species as side A
  --play=<species>         you play side A against the AI (the game only)
  --team=<a,b,...>         side A's whole team, 1-6 species in order; then --watch or --play
                           needs no species
  --vs=<species>           side B (default blastoise)
  --vs-team=<a,b,...>      side B's whole team instead of --vs
  --trainer=<trainer>      side A's trainer, or none (default in team battles: one from the seed,
                           otherwise none); --vs-trainer for B
  --ai=<profile>           side A's AI; with --play, the foe's (default ranked)
  --vs-ai=<profile>        side B's AI with --watch (default: --ai)
  --seed=<N>               the battle; without it each run is a new one
  --arena=<arena>          the arena; without it the seed picks one that suits the types
  --weather=<weather>      rain, sun, sand or snow for the whole battle, or none
  --moves=<a,b,...>        side A's moves (default: its standard moveset); --vs-moves for B
  --ability=<ability>      side A's ability, or none (default: its standard); --vs-ability for B
  --item=<item>            side A's held item, or none (default: its standard); --vs-item for B
  --shiny=a|b|both|none    which sides are shiny (default: rolled from the seed)
  --form=<form>            side A's cosmetic form, or base (default: rolled); --vs-form for B
Moves, ability, item and looks apply to a team's first member; the rest bring their standard
ones. Names may be written as IDs (mrmime, lifeorb) or as names ("Mr. Mime", "Life Orb")."""
const INFO_HELP := """Information:
  --list=<kind>            prints the species, arenas, moves, abilities, items, profiles or
                           trainers
  --help                   prints this help"""


## Whether `args` ask for help.
static func wants_help(args: PackedStringArray) -> bool:
	return args.has("--help") or args.has("-h")


## Handles --help (printing `help`) and --list=<kind>. Returns the exit code when it handled
## one, or -1 when `args` ask for neither.
static func info(args: PackedStringArray, help: String) -> int:
	if wants_help(args):
		print(help.strip_edges())
		return 0
	for arg in args:
		if arg == "--list" or arg.begins_with("--list="):
			var kind := arg.get_slice("=", 1) if arg.contains("=") else ""
			var data: BattleData = null
			if kind in ["species", "moves"]:
				var loaded := BattleData.load_all()
				if loaded.has("error"):
					printerr("error: " + loaded.error)
					return 1
				data = loaded.data
			var listed := list(kind, data)
			if listed.has("error"):
				printerr("error: " + listed.error)
				return 1
			print("\n".join(listed.lines))
			return 0
	return -1


## One line per entry of `kind` (LIST_KINDS), ID first: {"lines": PackedStringArray} or
## {"error"}. `data` is needed for species and moves.
static func list(kind: String, data: BattleData) -> Dictionary:
	var lines: PackedStringArray = []
	match kind:
		"species":
			for id: String in species_ids(data):
				var forms: Array = data.roster.get(id, {}).get("forms", {}).keys()
				forms.sort()
				lines.append("%s  %s%s" % [id, data.species[id].get("name", id),
					"  (forms: %s)" % ", ".join(forms) if not forms.is_empty() else ""])
		"arenas":
			for name in Arenas.names():
				var preset := Arenas.preset(name)
				lines.append("%s  %s (%s%s)" % [name, preset.get("name", name), preset.get("venue", "open"),
					", " + str(preset.weather) if preset.has("weather") else ""])
		"moves":
			for id: String in move_ids(data):
				var move: Dictionary = data.moves[id]
				lines.append("%s  %s (%s, %s%s)" % [id, move.get("name", id), move.get("type", ""), move.get("category", ""),
					", power %d" % int(move.basePower) if int(move.get("basePower", 0)) > 0 else ""])
		"abilities":
			for id in _sorted_keys(Abilities.table()):
				lines.append("%s  %s" % [id, Abilities.display_name(id)])
		"items":
			for id in _sorted_keys(Items.table()):
				lines.append("%s  %s" % [id, Items.display_name(id)])
		"profiles":
			for name in profiles():
				lines.append(name)
			lines.append("stand_in  (the stand-in AI)")
		"trainers":
			for id in TrainerView.ALL:
				lines.append("%s%s" % [id, "  (generic: the seed may pick it)" if id in TrainerView.GENERIC else ""])
		_:
			return {"error": "--list needs one of %s%s" % [", ".join(LIST_KINDS), _hint(nearest(kind, LIST_KINDS))]}
	return {"lines": lines}


## Every species a battle can use: the roster's (those with a model), or all of the data's when
## the roster isn't loaded.
static func species_ids(data: BattleData) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(data.roster.keys() if not data.roster.is_empty() else data.species.keys())
	ids = ids.filter(func(id: String) -> bool: return data.species.has(id))
	ids.sort()
	return ids


## Every move the rules can play (BattleMove.from_showdown converts it), sorted, without Z-moves,
## Max moves and made-up ones.
static func move_ids(data: BattleData) -> Array[String]:
	var ids: Array[String] = []
	for id: String in data.moves:
		var move: Dictionary = data.moves[id]
		if move.has("isZ") or move.has("isMax") or str(move.get("isNonstandard", "")) in ["CAP", "Custom"]:
			continue
		if not data.convert_move(id).has("error"):
			ids.append(id)
	ids.sort()
	return ids


## The AI profiles in Controllers.PROFILES_DIR, sorted.
static func profiles() -> Array[String]:
	var names: Array[String] = []
	for file in DirAccess.get_files_at(Controllers.PROFILES_DIR):
		# Exported builds list remapped resources with a .remap suffix.
		var name := file.trim_suffix(".remap")
		if name.get_extension() == "tres":
			names.append(name.get_basename())
	names.sort()
	return names


## Why `args` (what's left after a tool's own parsing) hold an unknown option, or "". `known`
## are the tool's own options, without "--"; SpecFlags.KEYS are known when `spec_flags`.
static func unknown_option(args: PackedStringArray, known: Array, spec_flags := true) -> String:
	var all: Array = known + ["help", "list"] + (Array(SpecFlags.KEYS) if spec_flags else [])
	for arg in args:
		if not arg.begins_with("-"):
			continue
		var key := arg.trim_prefix("--").trim_prefix("-").get_slice("=", 0)
		if spec_flags and key in SpecFlags.KEYS and not arg.contains("="):
			return "%s needs a value (--%s=...)" % [arg, key]
		if not key in all:
			return "unknown option %s (see --help)%s" % [arg, _hint(nearest(key, all).map(func(k: String) -> String: return "--" + k))]
	return ""


## Why the names in `spec` don't fit the data, or "": species, AIs, moves, abilities, items,
## the arena and the weather, each suggesting the nearest matches. Forms are Appearance.check's.
static func check_spec(spec: Dictionary, data: BattleData) -> String:
	var arena := str(spec.get("arena", ""))
	if not arena.is_empty() and not Arenas.all().has(arena):
		return unknown("arena", arena, Arenas.names())
	var weather := str(spec.get("weather", ""))
	if not weather.is_empty() and not weather in ArenaConditions.WEATHERS:
		return unknown("weather", weather, ArenaConditions.WEATHERS + [SpecFlags.NONE])
	var species := species_ids(data)
	var moves: Array[String] = []
	for side: Dictionary in spec.get("fighters", []):
		if not side.get("intents") is Array:
			var ai := str(side.get("ai", Controllers.DEFAULT_AI))
			if not ai in profiles() and not ai in OTHER_AIS:
				return unknown("AI profile", ai, profiles() + ["stand_in"])
	for side: Dictionary in spec.get("fighters", []):
		var trainer := Appearance.trainer_of(side)
		if not trainer.is_empty() and not trainer in TrainerView.ALL:
			return unknown("trainer", trainer, TrainerView.ALL + [Appearance.NO_TRAINER])
	for fighter: Dictionary in Appearance.members(spec):
		var id := str(fighter.get("species", ""))
		if not id in species:
			return unknown("species", id, species, BattleData.to_id)
		for move: String in fighter.get("moves", []):
			if not data.moves.has(move):
				if moves.is_empty():
					moves = move_ids(data)
				return unknown("move", move, moves, BattleData.to_id)
		for key: String in ["ability", "item"]:
			var value := str(fighter.get(key, ""))
			var table := Abilities.table() if key == "ability" else Items.table()
			if not value.is_empty() and not table.has(value):
				return unknown(key, value, _sorted_keys(table), BattleData.to_id)
	return ""


## "unknown <what> '<name>'", with the nearest of `candidates` as suggestions. `normalise`
## turns the name into the candidates' form before comparing.
static func unknown(what: String, name: String, candidates: Array, normalise := Callable()) -> String:
	var key: String = normalise.call(name) if normalise.is_valid() else name.to_lower()
	return "unknown %s '%s'%s" % [what, name, _hint(nearest(key, candidates))]


## Up to SUGGESTIONS of `candidates` nearest to `word`: those starting with it or containing it
## first, then by edit distance, keeping only plausible typos.
static func nearest(word: String, candidates: Array, count := SUGGESTIONS) -> Array:
	if word.is_empty():
		return []
	var scored: Array = []
	for candidate: String in candidates:
		var distance := edit_distance(word, candidate)
		if candidate.begins_with(word) or candidate.contains(word):
			distance = mini(distance, 1)
		if distance <= maxi(2, word.length() / 3):
			scored.append([distance, candidate])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return scored.slice(0, count).map(func(entry: Array) -> String: return entry[1])


## The Damerau–Levenshtein (optimal string alignment) distance: insertions, deletions,
## substitutions and swaps of neighbours each cost 1.
static func edit_distance(a: String, b: String) -> int:
	var before := PackedInt32Array()
	var previous := PackedInt32Array()
	previous.resize(b.length() + 1)
	for j in previous.size():
		previous[j] = j
	for i in range(1, a.length() + 1):
		var current := PackedInt32Array()
		current.resize(b.length() + 1)
		current[0] = i
		for j in range(1, b.length() + 1):
			var cost := 0 if a[i - 1] == b[j - 1] else 1
			current[j] = mini(mini(previous[j] + 1, current[j - 1] + 1), previous[j - 1] + cost)
			if i > 1 and j > 1 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1]:
				current[j] = mini(current[j], before[j - 2] + 1)
		before = previous
		previous = current
	return previous[b.length()]


## The battle as it was resolved, for the start of a run's output: the seed, arena and weather,
## then each fighter's AI, ability, item, moves and look. With `from_flags`, also the flags that
## repeat it exactly.
static func describe(spec: Dictionary, battle: Battle, from_flags: bool) -> PackedStringArray:
	var weather := battle.conditions.weather
	var lines: PackedStringArray = ["battle: seed %d, arena %s, weather %s" % [int(spec.seed), battle.arena,
		weather if not weather.is_empty() else SpecFlags.NONE]]
	for side in 2:
		var side_entry: Dictionary = spec.fighters[side]
		var controller := "intents" if side_entry.get("intents") is Array else str(side_entry.get("ai", Controllers.DEFAULT_AI))
		var members := Battle.members_of(side_entry)
		for fighter: Fighter in battle.teams[side]:
			var entry: Dictionary = members[fighter.slot]
			var form := str(entry.get("form", ""))
			# A team's members are numbered after the side: A1, A2, ...
			var label: String = "AB"[side] + (str(fighter.slot + 1) if members.size() > 1 else "")
			lines.append("  %s: %s (%s), ability %s, item %s, moves %s, %s%s" % [label, fighter.name, controller,
				fighter.ability if not fighter.ability.is_empty() else SpecFlags.NONE,
				fighter.item if not fighter.item.is_empty() else SpecFlags.NONE,
				",".join(fighter.moves.map(func(m: BattleMove) -> String: return m.id)),
				"form " + form if not form.is_empty() else "own look", ", shiny" if entry.get("shiny", false) else ""])
	if from_flags:
		var repeat := spec.duplicate(true)
		repeat.arena = battle.arena
		lines.append("  repeat with: " + " ".join(SpecFlags.from_spec(repeat)))
	return lines


static func _hint(suggestions: Array) -> String:
	return "; did you mean %s?" % " or ".join(suggestions) if not suggestions.is_empty() else ""


static func _sorted_keys(table: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	keys.assign(table.keys())
	keys.sort()
	return keys
