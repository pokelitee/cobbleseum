class_name Movesets
extends RefCounted
## One deterministic standard moveset per species (concepts_brief.md §9.6), generated from
## its learnset in every generation by a single policy:
## 1-2. two attacks of its own types (the second of its type again if it has only one),
##      preferring its better attacking stat;
## 3.   one coverage attack, worth more for each type it hits super effectively that the
##      first two don't;
## 4.   one utility move (sleep, paralysis, a buff to its attacking stat, a heal, ...) if one
##      scores at least UTILITY_THRESHOLD after accuracy, else a third attack.
## Only moves the rules can play are eligible. Ties break by move id, so the same data
## always gives the same moveset.

## Forms with fewer learnable moves than this (Rotom's appliances, cosmetic forms) also
## learn their base species' moves.
const FORM_LEARNSET_MIN := 25
## Attacks using the weaker attacking stat are worth this much.
const OFF_STAT_FACTOR := 0.6
const CHARGE_FACTOR := 0.75
const RECHARGE_FACTOR := 0.8
const RECOIL_FACTOR := 0.9
const SELF_DESTRUCT_FACTOR := 0.2
## Fixed-damage moves are valued like an attack of this power.
const FIXED_DAMAGE_VALUE := 80.0
## A coverage attack's value rises by this share per newly covered type.
const COVERAGE_BONUS := 0.25
## Utility scores, compared against UTILITY_THRESHOLD.
const UTILITY_THRESHOLD := 80.0
const STATUS_VALUES := {"slp": 110.0, "par": 95.0, "brn": 85.0, "tox": 85.0, "psn": 60.0, "frz": 60.0}
const CONFUSION_VALUE := 55.0
const HEAL_VALUE := 90.0
const BUFF_BASE := 75.0
const BUFF_PER_STAGE := 15.0
const DEBUFF_VALUE := 40.0
const TYPES: Array[String] = ["Normal", "Fire", "Water", "Electric", "Grass", "Ice", "Fighting", "Poison",
	"Ground", "Flying", "Psychic", "Bug", "Rock", "Ghost", "Dragon", "Dark", "Steel", "Fairy"]


## Returns {"moves": [4 move ids]} (fewer if the species can't fill four slots) or {"error"}.
static func generate(species_id: String, data: BattleData) -> Dictionary:
	var species: Dictionary = data.species.get(species_id, {})
	if species.is_empty():
		return {"error": "unknown species '%s'" % species_id}
	var physical := int(species.baseStats.atk) >= int(species.baseStats.spa)
	var types: Array = species.get("types", ["Normal"])
	var attacks: Array[Dictionary] = []
	var utilities: Array[Dictionary] = []
	for move_id in learnable(species_id, data):
		var converted := BattleMove.from_showdown(move_id, data.moves.get(move_id, {}))
		if converted.has("error"):
			continue
		var move: BattleMove = converted.move
		if move.is_damaging():
			attacks.append({"id": move_id, "type": move.type, "value": attack_value(move, data.moves[move_id], physical)})
		else:
			var accuracy: Variant = data.moves[move_id].get("accuracy", 100)
			var score := utility_value(move, physical) * (1.0 if accuracy is bool else float(accuracy) / 100.0)
			if score > 0.0:
				utilities.append({"id": move_id, "value": score})
	if attacks.is_empty():
		return {"error": "%s learns no playable attack" % species_id}

	var picked: Array[String] = []
	var own := attacks.filter(func(a: Dictionary) -> bool: return a.type in types)
	for type: String in types:
		_take(picked, _best(own.filter(func(a: Dictionary) -> bool: return a.type == type), picked))
	if picked.size() < 2:
		_take(picked, _best(own, picked))
	var covered := _covered(picked.map(func(id: String) -> String: return data.moves[id].type), data)
	var coverage := attacks.filter(func(a: Dictionary) -> bool: return not a.type in types).map(func(a: Dictionary) -> Dictionary:
		var gained := 0
		for defender in TYPES:
			if not covered.has(defender) and data.effectiveness(a.type, [defender]) >= 2.0:
				gained += 1
		return {"id": a.id, "value": a.value * (1.0 + COVERAGE_BONUS * gained)})
	_take(picked, _best(coverage, picked))
	var utility := _best(utilities, picked)
	if not utility.is_empty() and utility.value >= UTILITY_THRESHOLD:
		_take(picked, utility)
	while picked.size() < 4:
		var extra := _best(attacks, picked)
		if extra.is_empty():
			extra = _best(utilities, picked)
		if extra.is_empty():
			break
		_take(picked, extra)
	return {"moves": picked}


## Every move the species can learn: its own learnset, its pre-evolutions', and its base
## species' for forms with few moves of their own. Sorted, so iteration order never matters.
static func learnable(species_id: String, data: BattleData) -> Array[String]:
	var found := {}
	var chain: Array[String] = [species_id]
	var species: Dictionary = data.species.get(species_id, {})
	var own: Dictionary = data.learnsets.get(species_id, {}).get("learnset", {})
	if species.has("baseSpecies") and own.size() < FORM_LEARNSET_MIN:
		chain.append(BattleData.to_id(species.baseSpecies))
	var index := 0
	while index < chain.size():
		var id := chain[index]
		index += 1
		for move_id: String in data.learnsets.get(id, {}).get("learnset", {}):
			found[move_id] = true
		var prevo: String = data.species.get(id, {}).get("prevo", "")
		if not prevo.is_empty() and not chain.has(BattleData.to_id(prevo)):
			chain.append(BattleData.to_id(prevo))
	var ids: Array[String] = []
	ids.assign(found.keys())
	ids.sort()
	return ids


## Expected value of an attack for a species attacking with `physical` stats.
static func attack_value(move: BattleMove, raw: Dictionary, physical: bool) -> float:
	var value := FIXED_DAMAGE_VALUE if move.fixed_damage > 0 else move.power * move.expected_hits()
	var accuracy: Variant = raw.get("accuracy", 100)
	value *= 1.0 if accuracy is bool else float(accuracy) / 100.0
	if move.fixed_damage == 0 and move.physical != physical:
		value *= OFF_STAT_FACTOR
	if move.charges:
		value *= CHARGE_FACTOR
	if move.recharges:
		value *= RECHARGE_FACTOR
	if move.recoil_share > 0.0:
		value *= RECOIL_FACTOR
	if move.self_destructs:
		value *= SELF_DESTRUCT_FACTOR
	return value


## How useful a non-damaging move is to a species attacking with `physical` stats.
static func utility_value(move: BattleMove, physical: bool) -> float:
	match move.kind:
		BattleMove.Kind.STATUS:
			return CONFUSION_VALUE if move.confuses else STATUS_VALUES.get(move.status, 0.0)
		BattleMove.Kind.HEAL:
			return HEAL_VALUE * move.heal_share * 2.0
		BattleMove.Kind.SELF_BUFF:
			var stat := "atk" if physical else "spa"
			if not move.boosts.has(stat):
				return 0.0
			var stages := 0
			for boosted: String in move.boosts:
				if boosted in [stat, "spe"]:
					stages += int(move.boosts[boosted])
			return BUFF_BASE + BUFF_PER_STAGE * stages
		BattleMove.Kind.DEBUFF:
			return DEBUFF_VALUE
	return 0.0


## Types that at least one of `move_types` hits super effectively.
static func _covered(move_types: Array, data: BattleData) -> Dictionary:
	var covered := {}
	for defender in TYPES:
		for attack_type: String in move_types:
			if data.effectiveness(attack_type, [defender]) >= 2.0:
				covered[defender] = true
	return covered


## The highest-value candidate not yet picked; ties go to the smaller id.
static func _best(candidates: Array, picked: Array[String]) -> Dictionary:
	var best := {}
	for candidate: Dictionary in candidates:
		if picked.has(candidate.id):
			continue
		if best.is_empty() or candidate.value > best.value or (is_equal_approx(candidate.value, best.value) and candidate.id < best.id):
			best = candidate
	return best


static func _take(picked: Array[String], candidate: Dictionary) -> void:
	if not candidate.is_empty() and picked.size() < 4:
		picked.append(candidate.id)
