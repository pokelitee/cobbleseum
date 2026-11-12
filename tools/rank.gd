extends SceneTree
## Species rankings (concepts_brief.md §13).
## Usage: godot --headless --path . --script res://tools/rank.gd -- <command> [options]
##   run      plays a sampled round robin: every species meets --opponents=20 random others,
##            every matchup from both sides with the same seed. --profile=ranked picks the AI,
##            --seed=1 the schedule, --jobs=N splits it over N processes, --limit=N uses only
##            N species (a pilot). Resumes: battles already stored are skipped.
##   matrix   plays a full round robin among the --top=24 species of the current ranking,
##            --repeats=5 seeds per matchup from both sides, for the matchup matrix.
##   report   fits Bradley-Terry ratings to every stored battle for the rules version and
##            profile, and writes results/rank/v<rules>/<profile>/ranking.json and ranking.md.
##   compare  ranks --profile against --against=hard on the battles both have played, and
##            prints the Spearman rank correlation (the AI-sensitivity check).
## Records are JSON Lines, one battle per line, in results/rank/v<rules>/<profile>/; ratings
## are always derived from them, never stored on their own.

const RESULTS_DIR := "res://results/rank"
const DEFAULT_OPPONENTS := 20
const DEFAULT_TOP := 24
## Seeds per matchup in the matchup matrix, each played from both sides.
const DEFAULT_REPEATS := 5
const PROGRESS_EVERY := 250
const REPORT_ROWS := 30


func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var options := {"command": "", "opponents": DEFAULT_OPPONENTS, "seed": 1, "profile": Controllers.DEFAULT_AI,
		"against": "hard", "jobs": 1, "shard": 0, "shards": 1, "limit": 0, "top": DEFAULT_TOP, "repeats": DEFAULT_REPEATS}
	for arg: String in args:
		if not arg.begins_with("--"):
			options.command = arg
			continue
		var key := arg.trim_prefix("--").get_slice("=", 0)
		if not options.has(key):
			return _fail("unknown option %s" % arg)
		options[key] = arg.get_slice("=", 1) if options[key] is String else arg.get_slice("=", 1).to_int()
	var loaded := BattleData.load_all()
	if loaded.has("error"):
		return _fail(loaded.error)
	var data: BattleData = loaded.data
	var err := ""
	match options.command:
		"run":
			err = _run(data, options, _pool(data, options), options.opponents, "s%do%d" % [options.seed, options.opponents])
		"matrix":
			var ranking := _ranking(options.profile)
			if ranking.is_empty():
				return _fail("no ranking yet for profile %s; use run first" % options.profile)
			var top := Ranking.order(ranking).slice(0, options.top)
			err = _run(data, options, top, -1, "matrix%d" % options.top)
		"report":
			err = _report(options.profile)
		"compare":
			err = _compare(options.profile, options.against)
		_:
			err = "usage: -- run|matrix|report|compare [options] (see tools/rank.gd)"
	if not err.is_empty():
		return _fail(err)
	quit(0)


## Every roster species with a standard moveset, or a seeded sample of --limit of them.
func _pool(data: BattleData, options: Dictionary) -> Array:
	var pool: Array = []
	for id: String in data.roster:
		if not data.standard_moveset(id).has("error"):
			pool.append(id)
	pool.sort()
	if options.limit > 0 and options.limit < pool.size():
		var random := SimRandom.new(options.seed)
		for i in range(pool.size() - 1, 0, -1):
			var j := int(random.next_u32() % (i + 1))
			var swap: String = pool[i]
			pool[i] = pool[j]
			pool[j] = swap
		pool = pool.slice(0, options.limit)
		pool.sort()
	return pool


## Plays the schedule (sampled with `opponents`, or a full round robin when -1) for this shard,
## or launches --jobs processes that each take a shard.
func _run(data: BattleData, options: Dictionary, pool: Array, opponents: int, tag: String) -> String:
	var matchups := Ranking.schedule(pool, opponents, options.seed) if opponents > 0 		else Ranking.round_robin(pool, options.seed, options.repeats)
	if options.jobs > 1:
		return _launch(options, matchups.size() * 2)
	var dir := _dir(options.profile)
	var done := _stored_keys(dir)
	var path := dir.path_join("%s_shard%d.jsonl" % [tag, options.shard])
	var file := open_for_append(path)
	var played := 0
	var started := Time.get_ticks_msec()
	for index in matchups.size():
		if index % options.shards != options.shard:
			continue
		var matchup: Dictionary = matchups[index]
		for swapped in [false, true]:
			var a: String = matchup.b if swapped else matchup.a
			var b: String = matchup.a if swapped else matchup.b
			if done.has(_key(a, b, matchup.seed)):
				continue
			file.store_line(JSON.stringify(play(data, a, b, int(matchup.seed), options.profile)))
			played += 1
			if played % PROGRESS_EVERY == 0:
				file.flush()
				print("shard %d: %d battles (%.0f ms each)" % [options.shard, played, float(Time.get_ticks_msec() - started) / played])
	file.close()
	print("shard %d: played %d new battles of %d matchups" % [options.shard, played, matchups.size()])
	return ""


## One battle as a record: {"a", "b", "seed", "result": "A"|"B"|"D", "ticks", "rules", "profile"}.
static func play(data: BattleData, a: String, b: String, seed: int, profile: String) -> Dictionary:
	var spec := {"seed": seed, "fighters": [{"species": a, "ai": profile}, {"species": b, "ai": profile}]}
	var battle: Battle = Battle.create(spec, data, Controllers.for_spec(spec).controllers).battle
	battle.run()
	var result: String = {Battle.Result.WIN_A: "A", Battle.Result.WIN_B: "B"}.get(battle.result, "D")
	return {"a": a, "b": b, "seed": seed, "result": result, "ticks": battle.tick,
		"rules": Rules.RULES_VERSION, "profile": profile}


## Starts --jobs copies of this command, one per shard, and waits for them.
func _launch(options: Dictionary, battles: int) -> String:
	print("playing %d battles over %d processes" % [battles, options.jobs])
	var pids: Array[int] = []
	for shard in options.jobs:
		var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/rank.gd", "--",
			options.command, "--seed=%d" % options.seed, "--opponents=%d" % options.opponents, "--profile=%s" % options.profile,
			"--limit=%d" % options.limit, "--top=%d" % options.top, "--repeats=%d" % options.repeats,
			"--shard=%d" % shard, "--shards=%d" % options.jobs]
		var pid := OS.create_process(OS.get_executable_path(), args)
		if pid <= 0:
			return "could not start process %d" % shard
		pids.append(pid)
	var started := Time.get_ticks_msec()
	while pids.any(func(pid: int) -> bool: return OS.is_process_running(pid)):
		OS.delay_msec(2000)
	print("all shards done in %.0f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	return ""


func _report(profile: String) -> String:
	var records := _records(_dir(profile))
	if records.is_empty():
		return "no battles stored for profile %s under rules v%d" % [profile, Rules.RULES_VERSION]
	var ratings := Ranking.bradley_terry(records)
	var ordered := Ranking.order(ratings)
	var in_matrix := _matrix_species(_dir(profile))
	var matrix_ids := ordered.filter(func(id: String) -> bool: return in_matrix.has(id))
	var matrix := Ranking.matchups(records, matrix_ids)
	var dir := _dir(profile)
	var report := {"rules": Rules.RULES_VERSION, "profile": profile, "battles": records.size(),
		"species": ordered.size(), "ranking": ordered.map(func(id: String) -> Dictionary:
			return {"species": id, "rating": snappedf(ratings[id].rating, 0.1), "battles": ratings[id].battles,
				"win_rate": snappedf(ratings[id].score / maxf(ratings[id].battles, 1), 0.001)}),
		"matrix": {"species": matrix_ids, "win_rates": matrix}}
	var file := FileAccess.open(dir.path_join("ranking.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	file = FileAccess.open(dir.path_join("ranking.md"), FileAccess.WRITE)
	file.store_string(markdown(report))
	file.close()
	print("%d battles, %d species (rules v%d, AI %s)" % [records.size(), ordered.size(), Rules.RULES_VERSION, profile])
	for i in mini(15, ordered.size()):
		var id: String = ordered[i]
		print("%3d. %-20s %6.0f  %d battles" % [i + 1, id, ratings[id].rating, ratings[id].battles])
	print("wrote %s" % dir.path_join("ranking.md"))
	return ""


func _compare(profile: String, against: String) -> String:
	var first := _ranking(profile)
	var second := _ranking(against)
	if first.is_empty() or second.is_empty():
		return "need stored battles for both %s and %s" % [profile, against]
	var a := Ranking.order(first)
	var b := Ranking.order(second)
	var rho := Ranking.spearman(a, b)
	print("Spearman rank correlation, %s vs %s: %.3f over %d species" % [profile, against, rho,
		a.filter(func(id: String) -> bool: return b.has(id)).size()])
	print("(1 = the same order; well below 0.9 would mean the AI, not the Pokémon, drives results)")
	return ""


## The report as Markdown: the top and bottom of the ranking, and the matchup matrix.
static func markdown(report: Dictionary) -> String:
	var lines: PackedStringArray = [
		"# Cobbleseum ranking",
		"",
		"Rules version %d, AI profile `%s`: %d battles, %d species. Ratings are Bradley–Terry strengths on an Elo-like scale (400 points = 10:1 odds, average 1500); draws count as half a win." % [
			report.rules, report.profile, report.battles, report.species],
		"",
	]
	var rows: Array = report.ranking
	for section in [["Top", rows.slice(0, REPORT_ROWS), 0], ["Bottom", rows.slice(maxi(0, rows.size() - 10)), maxi(0, rows.size() - 10)]]:
		lines.append("## %s" % section[0])
		lines.append("")
		lines.append("| Rank | Species | Rating | Battles | Win rate |")
		lines.append("|---:|---|---:|---:|---:|")
		for i in section[1].size():
			var row: Dictionary = section[1][i]
			lines.append("| %d | %s | %.0f | %d | %.1f%% |" % [section[2] + i + 1, row.species, row.rating, row.battles, row.win_rate * 100.0])
		lines.append("")
	var ids: Array = report.matrix.species
	if not ids.is_empty():
		var rates: Dictionary = report.matrix.win_rates
		lines.append("## Matchup matrix")
		lines.append("")
		lines.append("Row species' win rate against the column species (full round robin among these, both sides).")
		lines.append("")
		lines.append("| | " + " | ".join(ids) + " |")
		lines.append("|---|" + "---:|".repeat(ids.size()))
		for row in ids:
			var cells: PackedStringArray = []
			for column in ids:
				var key := "%s|%s" % [row, column]
				cells.append("" if row == column else ("%.0f%%" % (rates[key] * 100.0) if rates.has(key) else "–"))
			lines.append("| %s | %s |" % [row, " | ".join(cells)])
		lines.append("")
	return "\n".join(lines)


func _ranking(profile: String) -> Dictionary:
	var records := _records(_dir(profile))
	return Ranking.bradley_terry(records) if not records.is_empty() else {}


static func _dir(profile: String) -> String:
	var root := ProjectSettings.globalize_path(RESULTS_DIR)
	var dir := root.path_join("v%d" % Rules.RULES_VERSION).path_join(profile)
	DirAccess.make_dir_recursive_absolute(dir)
	var results := root.get_base_dir()
	if not FileAccess.file_exists(results.path_join(".gdignore")):
		FileAccess.open(results.path_join(".gdignore"), FileAccess.WRITE).close()
	return dir


## Every stored battle in a profile's folder.
static func _records(dir: String) -> Array:
	var records: Array = []
	for name in DirAccess.get_files_at(dir):
		if not name.ends_with(".jsonl"):
			continue
		for line in FileAccess.get_file_as_string(dir.path_join(name)).split("\n", false):
			var record: Variant = JSON.parse_string(line)
			if record is Dictionary:
				records.append(record)
	return records


## Opens a JSON Lines file at its end. A run killed mid-write leaves a partial last line; it's
## ended here so the next record starts on its own line (the partial one is skipped on read,
## and its battle is played again).
static func open_for_append(path: String) -> FileAccess:
	if not FileAccess.file_exists(path):
		return FileAccess.open(path, FileAccess.WRITE)
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	var length := file.get_length()
	if length > 0:
		file.seek(length - 1)
		var last := file.get_8()
		file.seek_end()
		if last != 10:
			file.store_string("
")
	return file


static func _stored_keys(dir: String) -> Dictionary:
	var keys := {}
	for record: Dictionary in _records(dir):
		keys[_key(record.a, record.b, int(record.seed))] = true
	return keys


static func _key(a: String, b: String, seed: int) -> String:
	return "%s|%s|%d" % [a, b, seed]


## The species of the matchup matrix, from the matrix battles stored.
static func _matrix_species(dir: String) -> Array:
	var ids := {}
	for name in DirAccess.get_files_at(dir):
		if name.begins_with("matrix") and name.ends_with(".jsonl"):
			for line in FileAccess.get_file_as_string(dir.path_join(name)).split("\n", false):
				var record: Variant = JSON.parse_string(line)
				if record is Dictionary:
					ids[record.a] = true
					ids[record.b] = true
	var ordered := ids.keys()
	ordered.sort()
	return ordered


func _fail(message: String) -> void:
	printerr("error: " + message)
	quit(1)
