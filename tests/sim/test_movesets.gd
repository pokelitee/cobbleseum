extends TestCase
## The standard moveset generator (concepts_brief.md §9.6), on small inline data.

const SPECIES := {
	"sprout": {"name": "Sprout", "types": ["Grass", "Poison"], "baseStats": {"hp": 80, "atk": 70, "def": 80, "spa": 100, "spd": 90, "spe": 80}},
	"bloom": {"name": "Bloom", "types": ["Grass", "Poison"], "baseStats": {"hp": 80, "atk": 70, "def": 80, "spa": 100, "spd": 90, "spe": 80}, "prevo": "Sprout"},
	"bloomwash": {"name": "Bloom-Wash", "baseSpecies": "Bloom", "forme": "Wash", "types": ["Grass", "Water"], "baseStats": {"hp": 80, "atk": 70, "def": 80, "spa": 100, "spd": 90, "spe": 80}},
	"rock": {"name": "Rock", "types": ["Rock"], "baseStats": {"hp": 80, "atk": 120, "def": 80, "spa": 40, "spd": 90, "spe": 80}},
	"blob": {"name": "Blob", "types": ["Normal"], "baseStats": {"hp": 80, "atk": 50, "def": 50, "spa": 50, "spd": 50, "spe": 50}},
}
const MOVES := {
	"gigadrain": {"name": "Giga Drain", "category": "Special", "type": "Grass", "basePower": 75, "accuracy": 100, "pp": 10, "flags": {}, "target": "normal"},
	"energyball": {"name": "Energy Ball", "category": "Special", "type": "Grass", "basePower": 90, "accuracy": 100, "pp": 10, "flags": {}, "target": "normal"},
	"powerwhip": {"name": "Power Whip", "category": "Physical", "type": "Grass", "basePower": 120, "accuracy": 85, "pp": 10, "flags": {"contact": 1}, "target": "normal"},
	"sludgebomb": {"name": "Sludge Bomb", "category": "Special", "type": "Poison", "basePower": 90, "accuracy": 100, "pp": 10, "flags": {}, "target": "normal"},
	"earthpower": {"name": "Earth Power", "category": "Special", "type": "Ground", "basePower": 90, "accuracy": 100, "pp": 10, "flags": {}, "target": "normal"},
	"psychic": {"name": "Psychic", "category": "Special", "type": "Psychic", "basePower": 90, "accuracy": 100, "pp": 10, "flags": {}, "target": "normal"},
	"sleeppowder": {"name": "Sleep Powder", "category": "Status", "type": "Grass", "basePower": 0, "accuracy": 75, "pp": 15, "flags": {"powder": 1}, "target": "normal", "status": "slp"},
	"hydropump": {"name": "Hydro Pump", "category": "Special", "type": "Water", "basePower": 110, "accuracy": 80, "pp": 5, "flags": {}, "target": "normal"},
	"stoneedge": {"name": "Stone Edge", "category": "Physical", "type": "Rock", "basePower": 100, "accuracy": 80, "pp": 5, "flags": {}, "target": "normal"},
	"rockslide": {"name": "Rock Slide", "category": "Physical", "type": "Rock", "basePower": 75, "accuracy": 90, "pp": 10, "flags": {}, "target": "allAdjacentFoes"},
	"earthquake": {"name": "Earthquake", "category": "Physical", "type": "Ground", "basePower": 100, "accuracy": 100, "pp": 10, "flags": {}, "target": "allAdjacent"},
	"swordsdance": {"name": "Swords Dance", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 20, "flags": {}, "target": "self", "boosts": {"atk": 2}},
	"nastyplot": {"name": "Nasty Plot", "category": "Status", "type": "Dark", "basePower": 0, "accuracy": true, "pp": 20, "flags": {}, "target": "self", "boosts": {"spa": 2}},
	"focuspunch": {"name": "Focus Punch", "category": "Physical", "type": "Fighting", "basePower": 150, "accuracy": 100, "pp": 20, "flags": {"contact": 1}, "target": "normal"},
	"splash": {"name": "Splash", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 40, "flags": {}, "target": "self"},
}
const TYPES := {
	"grass": {"damageTaken": {"Fire": 1, "Water": 2, "Grass": 2, "Poison": 1, "Ground": 2}},
	"water": {"damageTaken": {"Grass": 1, "Water": 2, "Fire": 2}},
	"fire": {"damageTaken": {"Water": 1, "Ground": 1, "Rock": 1, "Fire": 2, "Grass": 2}},
	"rock": {"damageTaken": {"Water": 1, "Grass": 1, "Ground": 1, "Fire": 2}},
	"poison": {"damageTaken": {"Ground": 1, "Psychic": 1, "Grass": 2, "Poison": 2}},
	"electric": {"damageTaken": {"Ground": 1}},
	"steel": {"damageTaken": {"Ground": 1, "Fire": 1, "Poison": 3}},
}
const LEARNSETS := {
	"sprout": {"learnset": {"sleeppowder": ["9L1"], "gigadrain": ["9L1"]}},
	"bloom": {"learnset": {"energyball": ["9M"], "powerwhip": ["9L1"], "sludgebomb": ["9M"], "earthpower": ["9M"], "psychic": ["9M"], "nastyplot": ["9M"]}},
	"bloomwash": {"learnset": {"hydropump": ["9L1"]}},
	"rock": {"learnset": {"stoneedge": ["9M"], "rockslide": ["9M"], "earthquake": ["9M"], "swordsdance": ["9M"], "focuspunch": ["9M"]}},
	"blob": {"learnset": {"splash": ["9L1"]}},
}


func _data() -> BattleData:
	return BattleData.new(SPECIES, MOVES, TYPES, LEARNSETS)


func test_two_own_type_attacks_on_the_better_attacking_stat() -> void:
	var moves: Array = Movesets.generate("bloom", _data()).moves
	assert_true(moves.has("energyball"), "special Grass attack over a physical one: %s" % [moves])
	assert_false(moves.has("powerwhip"))
	assert_true(moves.has("sludgebomb"), "the second type gets an attack too")


func test_coverage_prefers_new_super_effective_types() -> void:
	var moves: Array = Movesets.generate("bloom", _data()).moves
	assert_true(moves.has("earthpower"), "Ground hits Fire, Rock, Poison, Electric and Steel: %s" % [moves])
	assert_false(moves.has("psychic"))


func test_pre_evolution_moves_are_learnable() -> void:
	var learnable := Movesets.learnable("bloom", _data())
	assert_true(learnable.has("sleeppowder") and learnable.has("gigadrain"), str(learnable))


func test_utility_slot_weighs_accuracy() -> void:
	var moves: Array = Movesets.generate("bloom", _data()).moves
	assert_eq(moves.size(), 4)
	assert_true(moves.has("nastyplot"), "+2 to its attacking stat beats 75%%-accurate sleep: %s" % [moves])
	var learnsets := LEARNSETS.duplicate(true)
	learnsets.bloom.learnset.erase("nastyplot")
	var data := BattleData.new(SPECIES, MOVES, TYPES, learnsets)
	assert_true(Movesets.generate("bloom", data).moves.has("sleeppowder"), "without the buff, sleep clears the threshold")


func test_forms_with_few_moves_learn_their_base_species_moves() -> void:
	var learnable := Movesets.learnable("bloomwash", _data())
	assert_true(learnable.has("hydropump") and learnable.has("energyball") and learnable.has("gigadrain"), str(learnable))
	assert_true(Movesets.generate("bloomwash", _data()).moves.has("hydropump"), "its own Water type gets an attack")


func test_physical_attacker_with_one_type() -> void:
	var moves: Array = Movesets.generate("rock", _data()).moves
	assert_true(moves.has("stoneedge") and moves.has("rockslide"), "two Rock attacks for a mono-Rock species: %s" % [moves])
	assert_true(moves.has("earthquake"))
	assert_true(moves.has("swordsdance"), "buffs its attacking stat")
	assert_false(moves.has("focuspunch"), "moves needing code are never picked")


func test_species_without_attacks_fail_clearly() -> void:
	assert_true(Movesets.generate("blob", _data()).error.contains("no playable attack"))


func test_generation_is_deterministic() -> void:
	assert_eq(Movesets.generate("bloom", _data()), Movesets.generate("bloom", _data()))


func test_battles_use_the_standard_moveset_when_the_spec_has_none() -> void:
	var spec := {"seed": 1, "fighters": [{"species": "rock"}, {"species": "bloom", "moves": ["gigadrain"]}]}
	var created := Battle.create(spec, _data(), SimpleAI.pair(1))
	assert_false(created.has("error"), str(created.get("error", "")))
	var ids: Array = created.battle.fighters[0].moves.map(func(m: BattleMove) -> String: return m.id)
	assert_eq(ids, Movesets.generate("rock", _data()).moves)
	assert_eq(created.battle.fighters[1].moves.size(), 1)
