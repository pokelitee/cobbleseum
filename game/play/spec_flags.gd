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
## Team battles (§9.1): --team=<a,b,...> and --vs-team=<a,b,...> list each side's whole team in
## order (1-6); --watch and --play may then come without a species (or name the team's first),
## and --vs may be left out. The flags about moves, ability, item and looks apply to each side's
## first member; the rest bring their standard ones.
## Species, moves, abilities and items may be written as names ("Mr. Mime", "Life Orb"); they
## become Showdown IDs. Cli checks them against the data.

const DEFAULT_FOE := "blastoise"
const KEYS: Array[String] = ["play", "watch", "vs", "team", "vs-team", "ai", "vs-ai", "seed", "arena", "weather", "shiny",
	"form", "vs-form", "moves", "vs-moves", "ability", "vs-ability", "item", "vs-item", "trainer", "vs-trainer"]
## Flags that may come without a value: the mode, when --team names the species.
const BARE_KEYS: Array[String] = ["play", "watch"]
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
		elif arg.begins_with("--") and not arg.contains("=") and key in BARE_KEYS:
			flags[key] = ""
		else:
			rest.append(arg)
	return {"flags": flags, "rest": rest}


## The spec the flags describe, {} when they name no battle (neither --play nor --watch), or
## {"error": String}.
static func to_spec(flags: Dictionary) -> Dictionary:
	if not flags.has("play") and not flags.has("watch"):
		return {}
	if flags.has("play") and flags.has("watch"):
		return {"error": "use --play or --watch, not both"}
	var playing := flags.has("play")
	if playing and flags.has("vs-ai"):
		return {"error": "--vs-ai is for --watch; with --play, --ai sets the foe's AI"}
	var seed := str(flags.get("seed", ""))
	if flags.has("seed") and not seed.is_valid_int():
		return {"error": "--seed must be a whole number, not '%s'" % seed}
	var ai: String = flags.get("ai", Controllers.DEFAULT_AI)
	var sides := [{"ai": "player" if playing else ai}, {"ai": ai if playing else flags.get("vs-ai", ai)}]
	for side in 2:
		var species_key: String = (["play" if playing else "watch", "vs"])[side]
		var team_key: String = ["team", "vs-team"][side]
		var named := BattleData.to_id(str(flags.get(species_key, "")))
		if flags.has(team_key):
			var team: Array = []
			for name in str(flags[team_key]).split(","):
				if not BattleData.to_id(name).is_empty():
					team.append({"species": BattleData.to_id(name)})
			if team.is_empty() or team.size() > Rules.MAX_TEAM:
				return {"error": "--%s lists 1-%d species, not %d" % [team_key, Rules.MAX_TEAM, team.size()]}
			if not named.is_empty() and named != team[0].species:
				return {"error": "--%s names %s, but --%s starts with %s" % [species_key, named, team_key, team[0].species]}
			sides[side].team = team
		elif side == 0 and named.is_empty():
			return {"error": "--%s needs a species, or --team to list side A's team" % species_key}
		else:
			sides[side].species = named if not named.is_empty() else DEFAULT_FOE
	var spec := {"seed": seed.to_int() if seed.is_valid_int() else int(Time.get_ticks_usec() % 1000000), "fighters": sides}
	if flags.has("arena"):
		spec.arena = flags.arena
	if flags.has("weather"):
		spec.weather = "" if flags.weather == NONE else str(flags.weather)
	if flags.has("shiny"):
		if not SHINY_SIDES.has(flags.shiny):
			return {"error": "--shiny must be a, b, both or none, not '%s'" % flags.shiny}
		for side in 2:
			lead(spec, side).shiny = SHINY_SIDES[flags.shiny][side]
	for side in 2:
		var key: String = ["form", "vs-form"][side]
		if flags.has(key):
			lead(spec, side).form = "" if flags[key] == Appearance.BASE_FORM else str(flags[key])
		var trainer_key: String = ["trainer", "vs-trainer"][side]
		if flags.has(trainer_key):
			sides[side].trainer = str(flags[trainer_key]).to_lower()
	for side in 2:
		var prefix: String = ["", "vs-"][side]
		if flags.has(prefix + "moves"):
			var moves: Array = []
			for name in str(flags[prefix + "moves"]).split(","):
				if not BattleData.to_id(name).is_empty():
					moves.append(BattleData.to_id(name))
			if moves.is_empty():
				return {"error": "--%smoves names no moves" % prefix}
			lead(spec, side).moves = moves
		for key: String in ["ability", "item"]:
			if flags.has(prefix + key):
				var value := str(flags[prefix + key])
				lead(spec, side)[key] = "" if value == NONE else BattleData.to_id(value)
	return spec


## The spec entry of `side`'s first team member (the side's own entry for a team of one).
static func lead(spec: Dictionary, side: int) -> Dictionary:
	return Battle.members_of(spec.fighters[side])[0]


## Flags that describe `spec` exactly (seed included), for passing a battle on to another process.
static func from_spec(spec: Dictionary) -> PackedStringArray:
	var flags := to_flags(spec)
	return to_args(flags)


## The flags {key: value} that describe `spec` (see from_spec()). A spec without a seed gives
## flags without one, so each battle they start gets a new seed. Of a team's members past the
## first, only the species are kept.
static func to_flags(spec: Dictionary) -> Dictionary:
	var sides: Array = spec.fighters
	var ais: Array = sides.map(func(f: Dictionary) -> String: return str(f.get("ai", Controllers.DEFAULT_AI)))
	var playing: bool = ais[0] == "player"
	var fighters: Array = [lead(spec, 0), lead(spec, 1)]
	var flags := {("play" if playing else "watch"): fighters[0].species, "vs": fighters[1].species,
		"ai": ais[1] if playing else ais[0]}
	for side in 2:
		if sides[side].has("trainer"):
			flags[["trainer", "vs-trainer"][side]] = sides[side].trainer
		if sides[side].get("team") is Array:
			flags[["team", "vs-team"][side]] = ",".join(sides[side].team.map(func(m: Dictionary) -> String: return str(m.species)))
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
