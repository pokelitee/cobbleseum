class_name SpecFlags
extends RefCounted
## Battle specs from command-line flags, so a battle can be started without a spec file
## (concepts_brief.md §10). Shared by the battle view and tools/record.gd.
## - --play=<species>: the player against --vs, which --ai controls.
## - --watch=<species>: AI against AI; --ai controls it and --vs-ai (default: --ai) its foe.
## --vs defaults to DEFAULT_FOE and --seed to one from the clock; --arena picks the arena and
## --weather a starting weather that lasts the battle (§9.11; "none" for none).
## How the fighters look (Appearance, presentation only): --shiny=a|b|both|none makes them shiny or
## not, and --form=<form> and --vs-form=<form> pick each one's cosmetic form ("base" for its
## own look). What the flags leave out is rolled from the seed once the roster is loaded.
## What each fighter brings (§9.6, §9.9, §9.10): --moves=<a,b,...>, --ability=<ability> and
## --item=<item> for the first, --vs-moves, --vs-ability and --vs-item for its foe; "none" for no
## ability or item. Left out, a fighter brings its species' standard ones.
## Species, moves, abilities and items may be written as names ("Mr. Mime", "Life Orb"); they
## become Showdown IDs. Cli checks them against the data.

const DEFAULT_FOE := "blastoise"
const KEYS: Array[String] = ["play", "watch", "vs", "ai", "vs-ai", "seed", "arena", "weather", "shiny", "form", "vs-form",
	"moves", "vs-moves", "ability", "vs-ability", "item", "vs-item"]
## The value of --ability, --item and --weather for none.
const NONE := "none"
## Which sides --shiny makes shiny.
const SHINY_SIDES := {"a": [true, false], "b": [false, true], "both": [true, true], "none": [false, false]}


## Splits `args` into these flags {key: value} and every other argument.
static func parse(args: PackedStringArray) -> Dictionary:
	var flags := {}
	var rest: PackedStringArray = []
	for arg in args:
		var key := arg.trim_prefix("--").get_slice("=", 0)
		if arg.begins_with("--") and arg.contains("=") and key in KEYS:
			flags[key] = arg.get_slice("=", 1)
		else:
			rest.append(arg)
	return {"flags": flags, "rest": rest}


## The spec the flags describe, {} when they name no battle (neither --play nor --watch), or
## {"error": String}.
static func to_spec(flags: Dictionary) -> Dictionary:
	var play: String = flags.get("play", "")
	var watch: String = flags.get("watch", "")
	if play.is_empty() and watch.is_empty():
		return {}
	if not play.is_empty() and not watch.is_empty():
		return {"error": "use --play or --watch, not both"}
	if not play.is_empty() and flags.has("vs-ai"):
		return {"error": "--vs-ai is for --watch; with --play, --ai sets the foe's AI"}
	var seed := str(flags.get("seed", ""))
	if flags.has("seed") and not seed.is_valid_int():
		return {"error": "--seed must be a whole number, not '%s'" % seed}
	var ai: String = flags.get("ai", Controllers.DEFAULT_AI)
	var foe: String = flags.get("vs", DEFAULT_FOE)
	var spec := {"seed": seed.to_int() if seed.is_valid_int() else int(Time.get_ticks_usec() % 1000000), "fighters": [
		{"species": BattleData.to_id(play if watch.is_empty() else watch), "ai": "player" if watch.is_empty() else ai},
		{"species": BattleData.to_id(foe), "ai": ai if watch.is_empty() else flags.get("vs-ai", ai)},
	]}
	if flags.has("arena"):
		spec.arena = flags.arena
	if flags.has("weather"):
		spec.weather = "" if flags.weather == NONE else str(flags.weather)
	if flags.has("shiny"):
		if not SHINY_SIDES.has(flags.shiny):
			return {"error": "--shiny must be a, b, both or none, not '%s'" % flags.shiny}
		for side in 2:
			spec.fighters[side].shiny = SHINY_SIDES[flags.shiny][side]
	for side in 2:
		var key: String = ["form", "vs-form"][side]
		if flags.has(key):
			spec.fighters[side].form = "" if flags[key] == Appearance.BASE_FORM else str(flags[key])
	for side in 2:
		var prefix: String = ["", "vs-"][side]
		if flags.has(prefix + "moves"):
			var moves: Array = []
			for name in str(flags[prefix + "moves"]).split(","):
				if not BattleData.to_id(name).is_empty():
					moves.append(BattleData.to_id(name))
			if moves.is_empty():
				return {"error": "--%smoves names no moves" % prefix}
			spec.fighters[side].moves = moves
		for key: String in ["ability", "item"]:
			if flags.has(prefix + key):
				var value := str(flags[prefix + key])
				spec.fighters[side][key] = "" if value == NONE else BattleData.to_id(value)
	return spec


## Flags that describe `spec` exactly (seed included), for passing a battle on to another process.
static func from_spec(spec: Dictionary) -> PackedStringArray:
	var flags := to_flags(spec)
	return to_args(flags)


## The flags {key: value} that describe `spec` (see from_spec()). A spec without a seed gives
## flags without one, so each battle they start gets a new seed.
static func to_flags(spec: Dictionary) -> Dictionary:
	var fighters: Array = spec.fighters
	var ais: Array = fighters.map(func(f: Dictionary) -> String: return str(f.get("ai", Controllers.DEFAULT_AI)))
	var playing: bool = ais[0] == "player"
	var flags := {("play" if playing else "watch"): fighters[0].species, "vs": fighters[1].species,
		"ai": ais[1] if playing else ais[0]}
	if not playing:
		flags["vs-ai"] = ais[1]
	if spec.has("seed"):
		flags.seed = str(int(spec.seed))
	if spec.has("arena"):
		flags.arena = spec.arena
	if spec.has("weather"):
		flags.weather = spec.weather if not str(spec.weather).is_empty() else NONE
	flags.merge(_look_flags(fighters))
	for side in 2:
		var prefix: String = ["", "vs-"][side]
		if fighters[side].has("moves"):
			flags[prefix + "moves"] = ",".join(fighters[side].moves)
		for key: String in ["ability", "item"]:
			if fighters[side].has(key):
				flags[prefix + key] = fighters[side][key] if not str(fighters[side][key]).is_empty() else NONE
	return flags


## Command-line arguments for `flags`, in KEYS order.
static func to_args(flags: Dictionary) -> PackedStringArray:
	var args: PackedStringArray = []
	for key in KEYS:
		if flags.has(key):
			args.append("--%s=%s" % [key, flags[key]])
	return args


## The --shiny, --form and --vs-form flags for what the fighters' specs say about their looks.
static func _look_flags(fighters: Array) -> Dictionary:
	var flags := {}
	if fighters[0].has("shiny") or fighters[1].has("shiny"):
		var shiny := [bool(fighters[0].get("shiny", false)), bool(fighters[1].get("shiny", false))]
		flags.shiny = SHINY_SIDES.find_key(shiny)
	for side in 2:
		if fighters[side].has("form"):
			var form := str(fighters[side].form)
			flags[["form", "vs-form"][side]] = form if not form.is_empty() else Appearance.BASE_FORM
	return flags
