extends TestCase
## Abilities (concepts_brief.md §9.9): the standard ability, and a representative of each kind
## of effect in game/data/abilities.json. Small inline data, so CI needs no asset cache.

const STATS := {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}
const SPECIES := {
	"squirt": {"name": "Squirt", "types": ["Water"], "baseStats": STATS, "abilities": {"0": "Torrent", "H": "Rain Dish"}},
	"blaze": {"name": "Blaze", "types": ["Fire"], "baseStats": STATS, "abilities": {"0": "Blaze", "1": "Flash Fire"}},
	"plain": {"name": "Plain", "types": ["Normal"], "baseStats": STATS, "abilities": {"0": "Run Away"}},
}
const MOVES := {
	"jet": {"name": "Jet", "category": "Special", "type": "Water", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"quake": {"name": "Quake", "category": "Physical", "type": "Ground", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"kick": {"name": "Kick", "category": "Physical", "type": "Fighting", "basePower": 60, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"punch": {"name": "Punch", "category": "Physical", "type": "Normal", "basePower": 75, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1, "punch": 1}, "target": "normal"},
	"jabs": {"name": "Jabs", "category": "Physical", "type": "Fighting", "basePower": 20, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal", "multihit": [2, 5]},
	"growl": {"name": "Growl", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": 100, "pp": 40, "priority": 0, "flags": {}, "target": "normal", "boosts": {"atk": -1}},
	"zap": {"name": "Zap", "category": "Status", "type": "Electric", "basePower": 0, "accuracy": 100, "pp": 20, "priority": 0, "flags": {}, "target": "normal", "status": "par"},
}
const TYPES := {
	"fire": {"damageTaken": {"Water": 1, "Fire": 2}},
	"water": {"damageTaken": {"Fire": 2, "Water": 2}},
	"normal": {"damageTaken": {}},
}


## Plays one intent on its tick and nothing otherwise.
class Scripted extends RefCounted:
	var plan := {}

	func decide(battle: Battle, _side: int) -> Dictionary:
		return plan.get(battle.tick, {})


func _data() -> BattleData:
	return BattleData.new(SPECIES, MOVES, TYPES)


func _battle(abilities: Array, moves_a := ["kick", "jet"], moves_b := ["jet"], plan_a := {}, species := ["squirt", "blaze"]) -> Battle:
	var spec := {"seed": 1, "arena": "stadium", "fighters": [
		{"species": species[0], "moves": moves_a, "ability": abilities[0]},
		{"species": species[1], "moves": moves_b, "ability": abilities[1]}]}
	var scripted := Scripted.new()
	scripted.plan = plan_a
	var created := Battle.create(spec, _data(), [scripted, Scripted.new()])
	assert_false(created.has("error"), str(created.get("error", "")))
	var battle: Battle = created.battle
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	a.position = Vector2(0, -(1.0 + a.radius + b.radius) / 2.0)
	b.position = Vector2(0, (1.0 + a.radius + b.radius) / 2.0)
	return battle


func _run(battle: Battle, ticks: int) -> void:
	for i in ticks:
		battle.step()


func _abilities_shown(battle: Battle, side: int) -> Array:
	return battle.events.filter(func(e: Dictionary) -> bool: return e.type == "ability" and e.side == side) \
		.map(func(e: Dictionary) -> String: return e.ability)


func _factor(attacker: Fighter, defender: Fighter, move_id: String) -> float:
	var parts := Battle.damage_parts(attacker, defender, _data().convert_move(move_id).move, _data())
	return parts.base * parts.factor


func test_the_standard_ability_is_the_best_implemented_one() -> void:
	assert_eq(Abilities.standard(SPECIES.blaze), "flashfire", "Flash Fire is valued over Blaze")
	assert_eq(Abilities.standard(SPECIES.squirt), "torrent", "Rain Dish isn't implemented (no weather)")
	assert_eq(Abilities.standard(SPECIES.plain), "", "nothing implemented, no ability")
	var created := Battle.create({"seed": 1, "fighters": [{"species": "blaze", "moves": ["jet"]}, {"species": "squirt", "moves": ["jet"]}]},
		_data(), [Scripted.new(), Scripted.new()])
	assert_eq(created.battle.fighters[0].ability, "flashfire", "a spec without one gets the standard ability")


func test_every_table_entry_is_a_known_effect() -> void:
	var keys := ["name", "value", "immune", "absorb_heal", "absorb_boosts", "absorb_power", "taken_types", "immune_flags",
		"pinch_type", "stat_factors", "stab", "technician", "flag_power", "recoil_power", "sheer_force",
		"status_stat_factors", "ignores_burn", "physical_projectile_speed", "tinted_lens", "super_effective_taken",
		"full_hp_taken", "contact_status", "contact_damage", "status_immune", "intimidate_immune", "sleep_factor",
		"shed_skin", "poison_heal", "ignores_paralysis", "synchronize", "intimidate", "no_lowering", "on_lowered",
		"hit_by_type", "on_physical_hit", "speed_boost", "sturdy", "no_recoil", "magic_guard", "secondary_chance",
		"skill_link", "shield_dust", "prankster", "sets_weather", "weather_stats", "weather_hp", "weather_power",
		"weather_immune", "weather_cures", "weather_status_immune"]
	for id: String in Abilities.table():
		assert_eq(id, BattleData.to_id(Abilities.display_name(id)), "%s is keyed by its Showdown ID" % id)
		for key: String in Abilities.table()[id]:
			assert_true(key in keys, "%s: unknown effect '%s'" % [id, key])


func test_a_spec_can_name_an_ability_or_none_but_not_an_unknown_one() -> void:
	var battle := _battle(["", "levitate"])
	assert_eq(battle.fighters[0].ability, "")
	assert_eq(battle.fighters[1].ability, "levitate")
	var spec := {"seed": 1, "fighters": [{"species": "blaze", "moves": ["jet"], "ability": "wonderguard"}, {"species": "squirt", "moves": ["jet"]}]}
	assert_true(Battle.create(spec, _data(), [Scripted.new(), Scripted.new()]).has("error"))


func test_an_ability_immunity_plays_like_a_type_immunity() -> void:
	var plain := _battle(["", ""])
	var floating := _battle(["", "levitate"])
	var ratio := _factor(floating.fighters[0], floating.fighters[1], "quake") / _factor(plain.fighters[0], plain.fighters[1], "quake")
	assert_almost_eq(ratio, Rules.compressed_effectiveness(0.0), 1e-6, "Ground hits Levitate at x0.25")


func test_an_absorb_heals_and_the_ais_avoid_feeding_it() -> void:
	var battle := _battle(["", "waterabsorb"], ["jet"], ["jet"], {0: {"use": 0}})
	var defender := battle.fighters[1]
	defender.hp = defender.max_hp / 2
	var before := defender.hp
	_run(battle, 30)
	assert_true(defender.hp > before, "Water Absorb heals more than the x0.25 hit takes")
	assert_true("waterabsorb" in _abilities_shown(battle, 1))
	var jet: BattleMove = battle.fighters[0].moves[0]
	assert_eq(StandInAI.move_score(battle.fighters[0], defender, jet), 0.0, "never worth attacking into")


func test_flash_fire_powers_up_its_own_fire_moves_after_absorbing() -> void:
	var battle := _battle(["", "flashfire"])
	var fighter := battle.fighters[1]
	var ember: BattleMove = BattleMove.from_showdown("ember", {"name": "Ember", "category": "Special", "type": "Fire", "basePower": 40,
		"accuracy": 100, "pp": 25, "flags": {}, "target": "normal"}).move
	assert_eq(Abilities.power_factor(fighter, ember), 1.0)
	fighter.flash_fire_ticks = 10
	assert_eq(Abilities.power_factor(fighter, ember), 1.5)


func test_damage_modifiers() -> void:
	var battle := _battle(["", ""])
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	var punch: BattleMove = _data().convert_move("punch").move
	var atk := a.stat("atk")
	a.set_ability("hugepower")
	assert_almost_eq(a.stat("atk"), atk * 2.0, 1e-6, "Huge Power")
	a.set_ability("ironfist")
	assert_almost_eq(Abilities.power_factor(a, punch), 1.2, 1e-6, "Iron Fist")
	a.set_ability("toughclaws")
	assert_almost_eq(Abilities.power_factor(a, punch), 1.3, 1e-6, "Tough Claws on a contact move")
	a.set_ability("torrent")
	var jet: BattleMove = _data().convert_move("jet").move
	assert_eq(Abilities.power_factor(a, jet), 1.0, "Torrent at full HP")
	a.hp = a.max_hp / 4
	assert_eq(Abilities.power_factor(a, jet), Abilities.PINCH_FACTOR, "Torrent in a pinch")
	b.set_ability("multiscale")
	assert_eq(Abilities.taken_factor(b, jet, 1.0), 0.5, "Multiscale at full HP")
	b.hp -= 1
	assert_eq(Abilities.taken_factor(b, jet, 1.0), 1.0)


func test_intimidate_drops_attack_and_abilities_answer_it() -> void:
	var battle := _battle(["intimidate", ""])
	battle.step()
	assert_eq(battle.fighters[1].boosts.atk, -1, "at the start")
	assert_true("intimidate" in _abilities_shown(battle, 0))
	_run(battle, Rules.seconds_to_ticks(Abilities.INTIMIDATE_SECONDS))
	assert_true(battle.fighters[1].boosts.atk < 0, "again while the battle goes on")
	for answer: Array in [["clearbody", 0], ["innerfocus", 0], ["defiant", 1]]:
		battle = _battle(["intimidate", answer[0]])
		battle.step()
		assert_eq(battle.fighters[1].boosts.atk, answer[1], answer[0])


func test_contact_punishers_hit_back_on_melee_strikes() -> void:
	var afflicted := 0
	for seed in 12:
		var battle := _battle(["", "static"], ["kick"], ["jet"], {0: {"use": 0}})
		battle._random = SimRandom.new(seed)
		_run(battle, 15)
		if battle.fighters[0].status == "par":
			afflicted += 1
	assert_true(afflicted > 0 and afflicted < 12, "Static's 30%%: %d of 12" % afflicted)
	var spiky := _battle(["", "roughskin"], ["kick"], ["jet"], {0: {"use": 0}})
	var hp := spiky.fighters[0].hp
	_run(spiky, 15)
	assert_true(spiky.fighters[0].hp < hp, "Rough Skin")
	var ranged := _battle(["", "roughskin"], ["jet"], ["jet"], {0: {"use": 0}})
	hp = ranged.fighters[0].hp
	_run(ranged, 30)
	assert_eq(ranged.fighters[0].hp, hp, "no contact, no damage")


func test_status_immunities_and_stat_protection() -> void:
	var battle := _battle(["", "limber"], ["zap"], ["jet"], {0: {"use": 0}})
	_run(battle, 40)
	assert_eq(battle.fighters[1].status, "", "Limber can't be paralysed")
	assert_eq(StandInAI.move_score(battle.fighters[0], battle.fighters[1], battle.fighters[0].moves[0]), 0.0,
		"the AI won't throw it")
	battle = _battle(["", "hypercutter"], ["growl"], ["jet"], {0: {"use": 0}})
	_run(battle, 40)
	assert_eq(battle.fighters[1].boosts.atk, 0, "Hyper Cutter keeps its Attack")


func test_sturdy_survives_one_knockout_blow() -> void:
	var battle := _battle(["", "sturdy"], ["kick"], ["jet"], {0: {"use": 0}, 30: {"use": 0}})
	var defender := battle.fighters[1]
	defender.hp = 2
	_run(battle, 15)
	assert_eq(defender.hp, 1, "holds on")
	battle.fighters[0].cooldowns[0] = 0
	_run(battle, 30)
	assert_true(defender.is_knocked_out(), "only once")


func test_skill_link_always_hits_the_most() -> void:
	var battle := _battle(["skilllink", ""], ["jabs"], ["jet"], {0: {"use": 0}})
	_run(battle, 40)
	var hits := battle.events.filter(func(e: Dictionary) -> bool: return e.type == "hit" and e.side == 0).size()
	assert_eq(hits, 5)


func test_speed_boost_raises_speed_over_time() -> void:
	var battle := _battle(["speedboost", ""])
	_run(battle, Rules.seconds_to_ticks(10.0) + 1)
	assert_eq(battle.fighters[0].boosts.spe, 1)


func test_magic_guard_and_poison_heal_ignore_status_damage() -> void:
	for ability: String in ["magicguard", "poisonheal"]:
		var battle := _battle([ability, ""])
		var fighter := battle.fighters[0]
		fighter.hp = fighter.max_hp / 2
		battle._inflict(fighter, "psn")
		var hp := fighter.hp
		_run(battle, 65)
		assert_true(fighter.hp >= hp, "%s: %d -> %d" % [ability, hp, fighter.hp])


func test_ability_state_is_in_the_checksum() -> void:
	var plain := _battle(["", ""])
	var boosted := _battle(["", ""])
	boosted.fighters[0].flash_fire_ticks = 50
	for each: Battle in [plain, boosted]:
		each.step()
		each.fighters[1].hp = 0
		each.step()
	assert_true(plain.checksum() != boosted.checksum())


func test_movesets_value_moves_the_standard_ability_boosts() -> void:
	var weak: BattleMove = BattleMove.from_showdown("tap", {"name": "Tap", "category": "Physical", "type": "Normal", "basePower": 40,
		"accuracy": 100, "pp": 30, "flags": {"contact": 1}, "target": "normal"}).move
	var raw := {"accuracy": 100}
	assert_almost_eq(Movesets.attack_value(weak, raw, true, "technician") / Movesets.attack_value(weak, raw, true), 1.5, 1e-6)
	var jabs: BattleMove = _data().convert_move("jabs").move
	assert_almost_eq(Movesets.attack_value(jabs, raw, true, "skilllink") / Movesets.attack_value(jabs, raw, true),
		5.0 / jabs.expected_hits(), 1e-6, "Skill Link values a 2-5-hit move at 5 hits")
