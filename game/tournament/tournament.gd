class_name Tournament
extends RefCounted
## Tournament mode (concepts_brief.md §17, M19): a single-elimination bracket of species (or
## teams of them), seeded from the species ranking (§13), played deterministically from its
## seed. Every game is an ordinary battle spec under the current rules, so a game plays and
## checksums exactly as the same spec does anywhere else.
##
## A tournament is a Dictionary, saved as tournament.json: the options, the seeding's source,
## "entrants" (best seed first) and, once played, "matches" in playing order and "champion".
## - create(): draws the field and seeds it.
## - play(): plays every match, game by game.
## - game_spec(): the battle spec of one game.
## parse() turns the command line's tournament flags into options.

const SIZES: Array[int] = [4, 8, 16, 32]
const DEFAULT_SIZE := 8
const BEST_OF: Array[int] = [1, 3, 5]
## The field is drawn by the seed from the top POOL_FACTOR times as many species as it needs,
## so each seed gives another bracket of strong species; --pool picks another pool.
const POOL_FACTOR := 4
## Drawn games a series may add on top of its best-of before the higher seed goes through.
const MAX_DRAWS := 3
## A doubles bracket's team size unless --team-size says otherwise: 2v2, the shortest doubles.
const DEFAULT_DOUBLES_TEAM := 2
## Random streams from the tournament seed.
const FIELD_STREAM := 1
## The flags. --tournament marks the game's command line (TournamentRun).
const KEYS: Array[String] = ["tournament", "size", "best-of", "team-size", "doubles", "ai", "seed", "pool", "entrants",
	"arena", "weather", "ranking"]
const BARE_KEYS: Array[String] = ["tournament", "doubles"]
## The value of --pool for every species.
const ALL := "all"
const HELP := """Tournament options:
  --size=8                 entrants: 4, 8, 16 or 32 (single elimination)
  --best-of=1              games a match: 1, 3 or 5 (drawn games are replayed)
  --team-size=1            species an entrant brings: 1 for one-on-one, 2-6 for team battles
  --doubles                doubles battles (teams of 2 unless --team-size says otherwise)
  --ai=ranked              the AI profile on every side
  --seed=<N>               the tournament: field, looks and every game; without it, a new one
  --pool=<N>|all           draw the field from the top N species (default: 4 times the field);
                           --pool equal to the field gives the top seeds straight
  --entrants=<a,b,...>     the field's species instead of a draw (size times team size)
  --arena=<arena>          every game's arena; without it each game's seed picks one
  --weather=<weather>      every game's weather: rain, sun, sand, snow or none
  --ranking=<file>         seed from this ranking.json; by default the newest under
                           results/rank/ for these rules, else by base stat total"""


## The options before any flags: an 8-entrant one-on-one tournament, best of one, by the ranked AI.
static func defaults() -> Dictionary:
	return {"size": DEFAULT_SIZE, "best_of": 1, "team_size": 1, "doubles": false, "ai": Controllers.DEFAULT_AI,
		"seed": -1, "pool": 0, "entrants": [], "arena": "", "weather": "", "ranking": ""}


## Whether `args` ask for a tournament (the game's --tournament).
static func wanted(args: PackedStringArray) -> bool:
	return args.has("--tournament")


## Splits `args` into tournament options (defaults() with the flags applied) and every other
## argument: {"options", "rest"}, or {"error"}. A missing --seed is drawn from the clock.
static func parse(args: PackedStringArray) -> Dictionary:
	var options := defaults()
	var rest: PackedStringArray = []
	var team_size_given := false
	for arg in args:
		var key := arg.trim_prefix("--").get_slice("=", 0)
		if not arg.begins_with("--") or not key in KEYS:
			rest.append(arg)
			continue
		var value := arg.get_slice("=", 1) if arg.contains("=") else ""
		if key in BARE_KEYS:
			if arg.contains("="):
				return {"error": "--%s takes no value" % key}
			if key == "doubles":
				options.doubles = true
			continue
		if value.is_empty():
			return {"error": "--%s needs a value (--%s=...)" % [key, key]}
		match key:
			"size", "best-of", "team-size", "seed":
				if not value.is_valid_int():
					return {"error": "--%s must be a whole number, not '%s'" % [key, value]}
				options[key.replace("-", "_")] = value.to_int()
				team_size_given = team_size_given or key == "team-size"
			"pool":
				if value != ALL and not (value.is_valid_int() and value.to_int() > 0):
					return {"error": "--pool must be a number of species or all, not '%s'" % value}
				options.pool = -1 if value == ALL else value.to_int()
			"entrants":
				options.entrants = Array(value.split(",", false)).map(func(name: String) -> String: return BattleData.to_id(name))
			_:
				options[key] = value
	if options.doubles and not team_size_given:
		options.team_size = DEFAULT_DOUBLES_TEAM
	var problem := check(options)
	if not problem.is_empty():
		return {"error": problem}
	if options.seed < 0:
		options.seed = int(Time.get_ticks_usec() % 1000000)
	return {"options": options, "rest": rest}


## Why `options` can't make a tournament, or "" (names are checked against the data later).
static func check(options: Dictionary) -> String:
	if not int(options.size) in SIZES:
		return "--size must be one of %s, not %d" % [", ".join(SIZES.map(func(s: int) -> String: return str(s))), options.size]
	if not int(options.best_of) in BEST_OF:
		return "--best-of must be 1, 3 or 5, not %d" % options.best_of
	if options.team_size < 1 or options.team_size > Rules.MAX_TEAM:
		return "--team-size must be 1-%d, not %d" % [Rules.MAX_TEAM, options.team_size]
	if options.doubles and options.team_size < Rules.MIN_DOUBLES_TEAM:
		return "--doubles needs a --team-size of %d-%d" % [Rules.MIN_DOUBLES_TEAM, Rules.MAX_TEAM]
	if not str(options.weather).is_empty() and not options.weather in ArenaConditions.WEATHERS + [SpecFlags.NONE]:
		return Cli.unknown("weather", options.weather, ArenaConditions.WEATHERS + [SpecFlags.NONE])
	return ""


## The newest ranking (§13) for `profile` under `rules_version` or an earlier one, read from
## results_dir/rank/v<rules>/<profile>/ranking.json: {"path", "rules", "battles", "ratings":
## {species: rating}}, or {} when there is none. A ranking under older rules is used rather than
## none: rules changes since have moved ratings little, and seeding only needs the order.
static func find_ranking(results_dir: String, profile: String, rules_version: int) -> Dictionary:
	var root := results_dir.path_join("rank")
	if not DirAccess.dir_exists_absolute(root):
		return {}
	var best := -1
	for name in DirAccess.get_directories_at(root):
		var version := name.trim_prefix("v")
		if name.begins_with("v") and version.is_valid_int() and version.to_int() <= rules_version and version.to_int() > best \
				and FileAccess.file_exists(root.path_join(name).path_join(profile).path_join("ranking.json")):
			best = version.to_int()
	if best < 0:
		return {}
	return load_ranking(root.path_join("v%d" % best).path_join(profile).path_join("ranking.json"))


## A ranking.json as written by tools/rank.gd report (see find_ranking()), or {"error"}.
static func load_ranking(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not (parsed is Dictionary and parsed.get("ranking") is Array):
		return {"error": "cannot read the ranking %s (write one with tools/rank.gd -- report)" % path}
	var ratings := {}
	for row: Variant in parsed.ranking:
		if row is Dictionary and row.has("species") and row.has("rating"):
			ratings[str(row.species)] = float(row.rating)
	return {"path": path, "rules": int(parsed.get("rules", 0)), "battles": int(parsed.get("battles", 0)), "ratings": ratings}


## Species that can enter, strongest first: every roster species with a standard moveset, those
## in `ratings` by rating and then the rest by base stat total (ties by id).
static func seeding_order(data: BattleData, ratings: Dictionary) -> Array:
	var ids: Array = Cli.species_ids(data).filter(func(id: String) -> bool: return not data.standard_moveset(id).has("error"))
	ids.sort_custom(func(x: String, y: String) -> bool:
		var ranked_x := ratings.has(x)
		if ranked_x != ratings.has(y):
			return ranked_x
		var a: float = ratings[x] if ranked_x else float(base_stat_total(data, x))
		var b: float = ratings[y] if ranked_x else float(base_stat_total(data, y))
		return a > b or (a == b and x < y))
	return ids


static func base_stat_total(data: BattleData, id: String) -> int:
	var total := 0
	for value: Variant in data.species[id].get("baseStats", {}).values():
		total += int(value)
	return total


## The tournament `options` describe, its field drawn and seeded by `ranking` (find_ranking();
## {} to seed by base stat total): {"tournament"} or {"error"}.
static func create(options: Dictionary, data: BattleData, ranking: Dictionary) -> Dictionary:
	var problem := check(options)
	if not problem.is_empty():
		return {"error": problem}
	var size: int = options.size
	var team_size: int = options.team_size
	var needed := size * team_size
	var ratings: Dictionary = ranking.get("ratings", {})
	var order := seeding_order(data, ratings)
	var field: Array = []
	if not options.entrants.is_empty():
		if options.entrants.size() != needed:
			return {"error": "--entrants lists %d species; %d entrants of %d need %d" % [options.entrants.size(), size, team_size, needed]}
		for id: String in options.entrants:
			if not Cli.species_ids(data).has(id):
				return {"error": Cli.unknown("species", id, Cli.species_ids(data), BattleData.to_id)}
			if not order.has(id):
				return {"error": "%s has no standard moveset, so it can't enter" % id}
			if field.has(id):
				return {"error": "--entrants lists %s twice" % id}
			field.append(id)
	else:
		if order.size() < needed:
			return {"error": "only %d species can enter; %d entrants of %d need %d" % [order.size(), size, team_size, needed]}
		var pool_size: int = order.size() if options.pool < 0 else (needed * POOL_FACTOR if options.pool == 0 else options.pool)
		field = draw(order.slice(0, clampi(pool_size, needed, order.size())), needed, SimRandom.stream(options.seed, FIELD_STREAM))
	field.sort_custom(func(x: String, y: String) -> bool: return order.find(x) < order.find(y))
	var entrants: Array = []
	# Teams are dealt by tier: entrant i brings the i-th strongest of each tier of `size`
	# species, so the first seed is the strongest in every tier and seeding still means something.
	for i in size:
		var members: Array = []
		for tier in team_size:
			members.append({"species": field[tier * size + i]})
		var entrant := {"seed": i + 1, "members": members, "name": entrant_name(data, members),
			"rating": snappedf(_mean(members.map(func(m: Dictionary) -> float:
				return ratings.get(m.species, float(base_stat_total(data, m.species))))), 0.1)}
		_roll_looks(entrant, int(options.seed), data.roster)
		entrants.append(entrant)
	var seeding := {"source": "ranking", "path": ranking.path, "rules": ranking.rules, "battles": ranking.battles} \
		if not ranking.is_empty() else {"source": "base stat total"}
	return {"tournament": {"options": options.duplicate(true), "rules_version": Rules.RULES_VERSION,
		"data_versions": data.versions.duplicate(), "seeding": seeding, "entrants": entrants}}


## A Fisher–Yates draw of `count` of `pool`, in draw order.
static func draw(pool: Array, count: int, random: SimRandom) -> Array:
	var ids := pool.duplicate()
	for i in mini(count, ids.size()):
		var j := i + int(random.next_u32() % (ids.size() - i))
		var swap: String = ids[i]
		ids[i] = ids[j]
		ids[j] = swap
	return ids.slice(0, count)


## A species' name, or "Team <lead's name>" for a team.
static func entrant_name(data: BattleData, members: Array) -> String:
	var lead := str(data.species.get(members[0].species, {}).get("name", members[0].species))
	return lead if members.size() == 1 else "Team " + lead


## Rolls each member's look (and a team's trainer) once for the whole tournament, from its
## seed, as Appearance rolls a battle's.
static func _roll_looks(entrant: Dictionary, seed: int, roster: Dictionary) -> void:
	var side := {"team": entrant.members}
	Appearance.roll_missing({"seed": derived_seed("%d|entrant|%d" % [seed, entrant.seed]), "fighters": [side]}, roster)
	if side.has("trainer"):
		entrant.trainer = side.trainer


static func _mean(values: Array) -> float:
	return values.reduce(func(sum: float, v: float) -> float: return sum + v, 0.0) / maxf(values.size(), 1)


static func derived_seed(text: String) -> int:
	return int(text.hash() & 0x7fffffff)


## The bracket's seeds by position, top to bottom: 1 v size, then the halves arranged so the
## top two seeds can only meet in the final ([1, 8, 4, 5, 2, 7, 3, 6] for 8).
static func bracket_order(size: int) -> Array[int]:
	var order: Array[int] = [1]
	while order.size() < size:
		var next: Array[int] = []
		var count := order.size() * 2
		for seed in order:
			next.append_array([seed, count + 1 - seed])
		order = next
	return order


static func rounds(size: int) -> int:
	return roundi(log(float(size)) / log(2.0))


## Matches in playing order: round by round, top to bottom, [{"round", "index"}].
static func schedule(size: int) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for round in rounds(size):
		for index in size >> (round + 1):
			list.append({"round": round, "index": index})
	return list


## The entrants (indices into "entrants") in a match's two slots, or -1 for a slot whose
## feeding match isn't decided in `matches` yet.
static func entrants_of(tournament: Dictionary, round: int, index: int, matches: Array) -> Array[int]:
	var order := bracket_order(tournament.options.size)
	var pair: Array[int] = []
	for slot in [index * 2, index * 2 + 1]:
		pair.append(order[slot] - 1 if round == 0 else winner_of(tournament, matches, round - 1, slot))
	return pair


## Who won match (`round`, `index`) in `matches`, or -1 if it isn't there.
static func winner_of(tournament: Dictionary, matches: Array, round: int, index: int) -> int:
	for bout: Dictionary in matches:
		if bout.round == round and bout.index == index:
			return bout.winner
	return -1


## "Final", "Semifinal 2", "Quarterfinal 3", "Round of 16 · Match 5".
static func match_title(size: int, round: int, index: int) -> String:
	var left := size >> round
	match left:
		2:
			return "Final"
		4:
			return "Semifinal %d" % (index + 1)
		8:
			return "Quarterfinal %d" % (index + 1)
	return "Round of %d · Match %d" % [left, index + 1]


## Game `game` of match (`round`, `index`): its battle seed.
static func game_seed(tournament: Dictionary, round: int, index: int, game: int) -> int:
	return derived_seed("%d|%d|%d|%d" % [tournament.options.seed, round, index, game])


## The battle spec of a game with entrant `a` on side A and `b` on side B: the rules and data
## versions, the seed, each side's fighter or team with its looks, and the tournament's arena,
## weather and doubles.
static func game_spec(tournament: Dictionary, a: int, b: int, seed: int) -> Dictionary:
	var options: Dictionary = tournament.options
	var sides: Array = []
	for index in [a, b]:
		var entrant: Dictionary = tournament.entrants[index]
		var side: Dictionary
		if entrant.members.size() == 1 and not options.doubles:
			side = entrant.members[0].duplicate(true)
		else:
			side = {"team": entrant.members.duplicate(true)}
			if entrant.has("trainer"):
				side.trainer = entrant.trainer
		side.ai = options.ai
		sides.append(side)
	var spec := {"rules_version": tournament.rules_version, "data_versions": tournament.data_versions.duplicate(),
		"seed": seed, "fighters": sides}
	if options.doubles:
		spec.doubles = true
	if not str(options.arena).is_empty():
		spec.arena = options.arena
	if not str(options.weather).is_empty():
		spec.weather = "" if options.weather == SpecFlags.NONE else options.weather
	return spec


## Plays every match in order, filling "matches" ([{"round", "index", "entrants": [a, b] (a the
## higher seed), "games", "wins", "winner", "by_seeding"}]) and "champion". Each game is
## {"seed", "sides": [entrant on A, on B], "result": "A"|"B"|"D", "winner" (entrant or -1),
## "ticks", "checksum"}. Sides swap every game; drawn games are replayed with the next seed, up to
## MAX_DRAWS beyond the best-of, after which the higher seed goes through.
## `on_game` is called with (tournament, match, game) after each game. Returns "" or an error.
static func play(tournament: Dictionary, data: BattleData, on_game := Callable()) -> String:
	var options: Dictionary = tournament.options
	var matches: Array = []
	tournament.matches = matches
	var to_win: int = options.best_of / 2 + 1
	for slot: Dictionary in schedule(options.size):
		var pair := entrants_of(tournament, slot.round, slot.index, matches)
		pair.sort()
		var bout := {"round": slot.round, "index": slot.index, "entrants": pair, "games": [], "wins": [0, 0]}
		var wins: Array = bout.wins
		while wins.max() < to_win and bout.games.size() < options.best_of + MAX_DRAWS:
			var number: int = bout.games.size()
			var sides: Array = [pair[1], pair[0]] if number % 2 == 1 else [pair[0], pair[1]]
			var spec := game_spec(tournament, sides[0], sides[1], game_seed(tournament, slot.round, slot.index, number))
			var controllers := Controllers.for_spec(spec)
			if controllers.has("error"):
				return controllers.error
			var created := Battle.create(spec, data, controllers.controllers)
			if created.has("error"):
				return created.error
			var battle: Battle = created.battle
			battle.run()
			var result: String = {Battle.Result.WIN_A: "A", Battle.Result.WIN_B: "B"}.get(battle.result, "D")
			var winner: int = sides[0] if result == "A" else (sides[1] if result == "B" else -1)
			if winner >= 0:
				wins[pair.find(winner)] += 1
			var game := {"seed": spec.seed, "sides": sides, "result": result, "winner": winner, "ticks": battle.tick,
				"checksum": battle.checksum()}
			bout.games.append(game)
			if on_game.is_valid():
				on_game.call(tournament, bout, game)
		bout.by_seeding = wins[0] == wins[1]
		bout.winner = pair[0] if wins[0] >= wins[1] else pair[1]
		matches.append(bout)
	tournament.champion = matches.back().winner
	return ""


## The tournament's seeding as text: the options, where the seeding came from, and each entrant
## with its rating (or base stat total) and species.
static func describe(tournament: Dictionary) -> PackedStringArray:
	var options: Dictionary = tournament.options
	var seeding: Dictionary = tournament.seeding
	var lines: PackedStringArray = ["tournament: seed %d, %d entrants, %s, best of %d, AI %s" % [options.seed, options.size,
		format_name(options), options.best_of, options.ai],
		"  seeded by %s" % ("the ranking %s (rules v%d, %d battles)" % [seeding.path, seeding.rules, seeding.battles]
			if seeding.source == "ranking" else "base stat total (no ranking found; tools/rank.gd makes one)")]
	for entrant: Dictionary in tournament.entrants:
		lines.append("  %2d. %-24s %7.1f  %s" % [entrant.seed, entrant.name, entrant.rating,
			",".join(entrant.members.map(func(m: Dictionary) -> String: return m.species + (" (shiny)" if m.get("shiny", false) else "")))])
	return lines


## A played tournament's results as text: each match's winner (with the series' score and its
## games, winner first, when it had several), then the champion.
static func results(tournament: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	for bout: Dictionary in tournament.get("matches", []):
		var names: Array = bout.entrants.map(func(i: int) -> String: return tournament.entrants[i].name)
		var first: int = bout.entrants.find(bout.winner)
		var score := ""
		if bout.games.size() > 1:
			score = " %d-%d [%s]" % [bout.wins[first], bout.wins[1 - first], " ".join(bout.games.map(func(g: Dictionary) -> String:
				return "draw" if g.winner < 0 else str(tournament.entrants[g.winner].seed)))]
		lines.append("  %-28s %s vs %s: %s wins%s%s" % [match_title(tournament.options.size, bout.round, bout.index), names[0], names[1],
			names[first], score, " (on seeding)" if bout.by_seeding else ""])
	if tournament.has("champion"):
		lines.append("champion: %s" % tournament.entrants[tournament.champion].name)
	return lines


## "singles", "3v3 singles", "2v2 doubles".
static func format_name(options: Dictionary) -> String:
	var kind := "doubles" if options.doubles else "singles"
	return kind if options.team_size == 1 else "%dv%d %s" % [options.team_size, options.team_size, kind]


## The tournament as it's shown, in order: a card before each match, the match's games, then
## the champion: [{"card": match}, {"match": m, "game": g}, ..., {"champion": true}].
static func reel(tournament: Dictionary) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	for m in tournament.matches.size():
		steps.append({"card": m})
		for g in tournament.matches[m].games.size():
			steps.append({"match": m, "game": g})
	steps.append({"champion": true})
	return steps


## Game `g` of match `m`'s battle spec.
static func spec_of(tournament: Dictionary, m: int, g: int) -> Dictionary:
	var game: Dictionary = tournament.matches[m].games[g]
	return game_spec(tournament, game.sides[0], game.sides[1], game.seed)


## A game's title for its intro card: its match's ("Semifinal 1"), with the game's number in a
## series or after a drawn game.
static func game_title(tournament: Dictionary, m: int, g: int) -> String:
	var bout: Dictionary = tournament.matches[m]
	var title := match_title(tournament.options.size, bout.round, bout.index)
	return title if bout.games.size() == 1 and tournament.options.best_of == 1 else "%s · Game %d" % [title, g + 1]


## A tournament read back from its JSON (JSON numbers are floats; whole ones become ints
## again), or {} if `text` isn't one.
static func from_json(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	return _whole_numbers(parsed) if parsed is Dictionary and parsed.has("entrants") else {}


static func _whole_numbers(value: Variant) -> Variant:
	if value is Dictionary:
		for key: Variant in value:
			value[key] = _whole_numbers(value[key])
	elif value is Array:
		for i in value.size():
			value[i] = _whole_numbers(value[i])
	elif value is float and value == floorf(value) and absf(value) < 9.0e15:
		return int(value)
	return value
