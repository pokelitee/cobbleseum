class_name Ranking
extends RefCounted
## Ranking maths (concepts_brief.md §13), kept free of files and processes so it can be tested.
## - schedule(): which matchups to play, sampled and seeded.
## - bradley_terry(): strengths fitted to all results, draws counting half a win each.
## - spearman(): rank correlation, for the AI-sensitivity check.

## Bradley-Terry fitting: iterations of the MM algorithm and when to stop.
const MAX_ITERATIONS := 2000
const TOLERANCE := 1e-9
## Each species also gets this many virtual draws against an average opponent, so a species
## that never won (or never lost) still gets a finite rating.
const PRIOR_BATTLES := 1.0
## Ratings are shown on an Elo-like scale: 400 points is 10:1 odds, the average is 1500.
const RATING_SCALE := 400.0
const RATING_MEAN := 1500.0


## Matchups for a sampled round robin: each species meets `opponents` others picked at random
## (so most meet a few more, as others pick them too). Returns unique unordered matchups
## [{"a", "b", "seed"}] with a ≤ b, sorted, each with its own battle seed. Every matchup is
## played from both sides with that seed.
static func schedule(pool: Array, opponents: int, seed: int) -> Array[Dictionary]:
	var ids: Array = pool.duplicate()
	ids.sort()
	var random := SimRandom.new(seed)
	var chosen := {}
	for i in ids.size():
		var picks := mini(opponents, ids.size() - 1)
		var taken := 0
		var guard := 0
		while taken < picks and guard < picks * 20:
			guard += 1
			var j := int(random.next_u32() % ids.size())
			if j == i:
				continue
			var key := "%s|%s" % [ids[mini(i, j)], ids[maxi(i, j)]]
			if not chosen.has(key):
				chosen[key] = true
				taken += 1
	var keys := chosen.keys()
	keys.sort()
	var matchup_list: Array[Dictionary] = []
	for key: String in keys:
		matchup_list.append({"a": key.get_slice("|", 0), "b": key.get_slice("|", 1),
			"seed": int(("%s|%d" % [key, seed]).hash() & 0x7fffffff)})
	return matchup_list


## A full round robin among `ids`, for the matchup matrix: every pair `repeats` times, each
## with its own seed (the first is the seed schedule() would give, so shared battles are reused).
static func round_robin(ids: Array, seed: int, repeats := 1) -> Array[Dictionary]:
	var sorted: Array = ids.duplicate()
	sorted.sort()
	var matchup_list: Array[Dictionary] = []
	for i in sorted.size():
		for j in range(i + 1, sorted.size()):
			var key := "%s|%s" % [sorted[i], sorted[j]]
			for repeat in repeats:
				var tag := "%s|%d" % [key, seed] if repeat == 0 else "%s|%d|%d" % [key, seed, repeat]
				matchup_list.append({"a": sorted[i], "b": sorted[j], "seed": int(tag.hash() & 0x7fffffff)})
	return matchup_list


## Fits Bradley-Terry strengths to battle records ({"a", "b", "result": "A"|"B"|"D"}).
## Returns {species: {"rating", "battles", "score"}} where score is wins plus half of draws.
static func bradley_terry(records: Array) -> Dictionary:
	var wins := {}
	var battles := {}
	var matchup_battles := {}
	for record: Dictionary in records:
		var a: String = record.a
		var b: String = record.b
		if a == b:
			continue
		for id in [a, b]:
			wins[id] = wins.get(id, 0.0)
			battles[id] = battles.get(id, 0)
		battles[a] += 1
		battles[b] += 1
		match record.result:
			"A":
				wins[a] += 1.0
			"B":
				wins[b] += 1.0
			_:
				wins[a] += 0.5
				wins[b] += 0.5
		var key := _pair_key(a, b)
		matchup_battles[key] = matchup_battles.get(key, 0) + 1
	var ids: Array = wins.keys()
	var strength := {}
	for id in ids:
		strength[id] = 1.0
	var opponents := {}
	for key: String in matchup_battles:
		var a := key.get_slice("|", 0)
		var b := key.get_slice("|", 1)
		opponents.get_or_add(a, []).append([b, matchup_battles[key]])
		opponents.get_or_add(b, []).append([a, matchup_battles[key]])
	for iteration in MAX_ITERATIONS:
		var next := {}
		var change := 0.0
		for id in ids:
			# MM update, with the prior as virtual draws against a strength-1 opponent.
			var denominator: float = PRIOR_BATTLES / (strength[id] + 1.0)
			for entry: Array in opponents.get(id, []):
				denominator += float(entry[1]) / (strength[id] + strength[entry[0]])
			next[id] = (wins[id] + PRIOR_BATTLES * 0.5) / denominator
		var log_mean := 0.0
		for id in ids:
			log_mean += log(next[id])
		log_mean /= maxf(ids.size(), 1)
		for id in ids:
			next[id] = next[id] / exp(log_mean)
			change = maxf(change, absf(log(next[id]) - log(strength[id])))
		strength = next
		if change < TOLERANCE:
			break
	var result := {}
	for id in ids:
		result[id] = {"rating": RATING_MEAN + RATING_SCALE * log(strength[id]) / log(10.0),
			"battles": battles[id], "score": wins[id]}
	return result


## Species ordered best first by rating (ties by id).
static func order(ratings: Dictionary) -> Array:
	var ids := ratings.keys()
	ids.sort_custom(func(x: String, y: String) -> bool:
		return ratings[x].rating > ratings[y].rating or (ratings[x].rating == ratings[y].rating and x < y))
	return ids


## Spearman rank correlation of two rankings over the species they share (1 = identical order).
static func spearman(first: Array, second: Array) -> float:
	var shared := first.filter(func(id: String) -> bool: return second.has(id))
	var n := shared.size()
	if n < 2:
		return 0.0
	var rank_second := {}
	var position := 0
	for id: String in second:
		if shared.has(id):
			rank_second[id] = position
			position += 1
	var sum := 0.0
	for i in n:
		var d: float = i - rank_second[shared[i]]
		sum += d * d
	return 1.0 - 6.0 * sum / (n * (n * n - 1.0))


## Head-to-head win rates (draws as half) between every pair in `ids` from records:
## {"a|b": share of battles a won against b}.
static func matchups(records: Array, ids: Array) -> Dictionary:
	var wanted := {}
	for id in ids:
		wanted[id] = true
	var score := {}
	var battles := {}
	for record: Dictionary in records:
		if not (wanted.has(record.a) and wanted.has(record.b)):
			continue
		var a_share := 1.0 if record.result == "A" else (0.0 if record.result == "B" else 0.5)
		for pair in [[record.a, record.b, a_share], [record.b, record.a, 1.0 - a_share]]:
			var key := "%s|%s" % [pair[0], pair[1]]
			score[key] = score.get(key, 0.0) + pair[2]
			battles[key] = battles.get(key, 0) + 1
	var rates := {}
	for key: String in battles:
		rates[key] = score[key] / battles[key]
	return rates


static func _pair_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]
