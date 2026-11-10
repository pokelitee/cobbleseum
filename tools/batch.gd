extends SceneTree
## Batch simulation and balance report (concepts_brief.md §9.7).
## Usage: godot --headless --path . --script res://tools/batch.gd -- [--battles=500] [--seed=1]
##        [--ai-a=ranked] [--ai-b=ranked]
## The AI options name each side's controller (Controllers): pitting two AIs against each
## other over random pairings, side A's win rate shows which is stronger.
##
## Runs random pairings of roster species with their standard movesets and the stand-in AI,
## then prints the numbers the rules are tuned against and writes them, with every battle's
## summary, to results/balance_<rules version>_<seed>.json:
## - battle length (median and spread) and draw rate;
## - how often the side with the type advantage wins;
## - how often each move kind is used, plus dodges, statuses and side bias.
## Pairings and battle seeds come from --seed, so a report can be reproduced exactly.

const DEFAULT_BATTLES := 500
const RESULTS_DIR := "res://results"
## Targets from the brief: battles of 30-45 s, few draws.
const TARGET_SECONDS := Vector2(30.0, 45.0)
const TARGET_DRAW_RATE := 0.05


func _initialize() -> void:
	var battles := DEFAULT_BATTLES
	var seed := 1
	var ai := [Controllers.DEFAULT_AI, Controllers.DEFAULT_AI]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--battles="):
			battles = maxi(1, arg.get_slice("=", 1).to_int())
		elif arg.begins_with("--seed="):
			seed = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--ai-a=") or arg.begins_with("--ai-b="):
			ai[0 if arg.begins_with("--ai-a=") else 1] = arg.get_slice("=", 1)
		else:
			printerr("error: unknown option %s" % arg)
			return quit(1)
	var loaded := BattleData.load_all()
	if loaded.has("error"):
		printerr("error: " + loaded.error)
		return quit(1)
	var data: BattleData = loaded.data
	var pool: Array[String] = []
	for id: String in data.roster:
		if not data.standard_moveset(id).has("error"):
			pool.append(id)
	pool.sort()

	var random := SimRandom.new(seed)
	var rows: Array[Dictionary] = []
	var started := Time.get_ticks_msec()
	for i in battles:
		var a := pool[random.next_u32() % pool.size()]
		var b := pool[random.next_u32() % pool.size()]
		var spec := {"seed": int(random.next_u32() % 1000000), "fighters": [{"species": a, "ai": ai[0]}, {"species": b, "ai": ai[1]}]}
		rows.append(run(spec, data))
	var elapsed := (Time.get_ticks_msec() - started) / 1000.0
	var report := summarise(rows)
	report.rules_version = Rules.RULES_VERSION
	report.seed = seed
	report.ai = ai
	report.ms_per_battle = elapsed * 1000.0 / battles
	print_report(report, pool.size())
	_save(report, rows, seed)
	quit(0)


## One battle's summary: result, length, advantage and event counts.
static func run(spec: Dictionary, data: BattleData) -> Dictionary:
	var battle: Battle = Battle.create(spec, data, Controllers.for_spec(spec).controllers).battle
	battle.run()
	var kinds := {}
	var counts := {}
	var moves_by_id := {}
	for fighter in battle.fighters:
		for move in fighter.moves:
			moves_by_id[move.id] = move
	for event in battle.events:
		counts[event.type] = counts.get(event.type, 0) + 1
		if event.type == "windup":
			var kind: String = BattleMove.Kind.keys()[moves_by_id[event.move].kind].to_lower()
			kinds[kind] = kinds.get(kind, 0) + 1
	return {
		"a": spec.fighters[0].species, "b": spec.fighters[1].species, "seed": spec.seed,
		"result": Battle.Result.keys()[battle.result], "seconds": battle.tick / float(Rules.TICK_RATE),
		"advantage": advantage(battle, data), "kinds": kinds, "events": counts,
	}


## 0 or 1 for the side whose best super-effective hit on the other is stronger, -1 if even.
static func advantage(battle: Battle, data: BattleData) -> int:
	var best := [0.0, 0.0]
	for side in 2:
		for move in battle.fighters[side].moves:
			if move.is_damaging() and move.fixed_damage == 0:
				best[side] = maxf(best[side], data.effectiveness(move.type, battle.fighters[1 - side].types))
	if is_equal_approx(best[0], best[1]):
		return -1
	return 0 if best[0] > best[1] else 1


static func summarise(rows: Array[Dictionary]) -> Dictionary:
	var seconds: Array[float] = []
	var draws := 0
	var a_wins := 0
	var decided := 0
	var advantaged := 0
	var advantaged_wins := 0
	var kinds := {}
	var events := {}
	for row in rows:
		seconds.append(row.seconds)
		if row.result == "DRAW":
			draws += 1
		else:
			decided += 1
			var winner := 0 if row.result == "WIN_A" else 1
			if winner == 0:
				a_wins += 1
			if row.advantage >= 0:
				advantaged += 1
				if winner == row.advantage:
					advantaged_wins += 1
		for kind: String in row.kinds:
			kinds[kind] = kinds.get(kind, 0) + row.kinds[kind]
		for type: String in row.events:
			events[type] = events.get(type, 0) + row.events[type]
	seconds.sort()
	var uses := 0
	for kind: String in kinds:
		uses += kinds[kind]
	var kind_shares := {}
	for kind: String in kinds:
		kind_shares[kind] = float(kinds[kind]) / maxi(uses, 1)
	var per_battle := {}
	for type in ["hit", "miss", "dodge", "dodged", "status", "boost", "heal", "faint", "time_up"]:
		per_battle[type] = float(events.get(type, 0)) / rows.size()
	return {
		"battles": rows.size(),
		"median_seconds": _percentile(seconds, 0.5), "p10_seconds": _percentile(seconds, 0.1),
		"p90_seconds": _percentile(seconds, 0.9),
		"draw_rate": float(draws) / rows.size(),
		"side_a_win_rate": float(a_wins) / maxi(decided, 1),
		"advantage_win_rate": float(advantaged_wins) / maxi(advantaged, 1), "advantaged_battles": advantaged,
		"move_kind_shares": kind_shares, "per_battle": per_battle,
	}


static func print_report(report: Dictionary, pool_size: int) -> void:
	print("%d battles from %d species (rules v%d, seed %d, AI %s vs %s), %.1f ms per battle" % [
		report.battles, pool_size, report.rules_version, report.seed, report.ai[0], report.ai[1], report.ms_per_battle])
	print("length: median %.1f s (target %d-%d), p10 %.1f s, p90 %.1f s" % [
		report.median_seconds, TARGET_SECONDS.x, TARGET_SECONDS.y, report.p10_seconds, report.p90_seconds])
	print("draws: %.1f%% (target under %d%%)" % [report.draw_rate * 100.0, TARGET_DRAW_RATE * 100.0])
	print("type advantage wins: %.1f%% of %d battles with an advantage" % [report.advantage_win_rate * 100.0, report.advantaged_battles])
	print("side A wins: %.1f%% of decided battles" % [report.side_a_win_rate * 100.0])
	var shares: Dictionary = report.move_kind_shares
	var kinds := shares.keys()
	kinds.sort_custom(func(x: String, y: String) -> bool: return shares[x] > shares[y])
	print("move kinds: %s" % ", ".join(kinds.map(func(k: String) -> String: return "%s %.1f%%" % [k, shares[k] * 100.0])))
	var per: Dictionary = report.per_battle
	print("per battle: %s" % ", ".join(per.keys().map(func(k: String) -> String: return "%s %.1f" % [k, per[k]])))


static func _percentile(sorted: Array[float], share: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[clampi(roundi(share * (sorted.size() - 1)), 0, sorted.size() - 1)]


## Results live inside the project folder, so keep the editor from importing them.
static func _save(report: Dictionary, rows: Array[Dictionary], seed: int) -> void:
	var dir := ProjectSettings.globalize_path(RESULTS_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	if not FileAccess.file_exists(dir.path_join(".gdignore")):
		FileAccess.open(dir.path_join(".gdignore"), FileAccess.WRITE).close()
	var path := dir.path_join("balance_v%d_%d.json" % [Rules.RULES_VERSION, seed])
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"report": report, "battles": rows}, "  ", false))
	file.close()
	print("wrote %s" % path)
