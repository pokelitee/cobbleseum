extends TestCase
## Held items (concepts_brief.md §9.10): the standard item, and each kind of effect in
## game/data/items.json. Small inline data, so CI needs no asset cache.

const SPECIES := {
	"squirt": {"name": "Squirt", "types": ["Water"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}},
	"tadpole": {"name": "Tadpole", "types": ["Water"], "baseStats": {"hp": 40, "atk": 50, "def": 40, "spa": 40, "spd": 40, "spe": 90}, "evos": ["Squirt"]},
	"wall": {"name": "Wall", "types": ["Rock"], "baseStats": {"hp": 100, "atk": 80, "def": 120, "spa": 50, "spd": 90, "spe": 30}},
	"cannon": {"name": "Cannon", "types": ["Fire"], "baseStats": {"hp": 60, "atk": 60, "def": 60, "spa": 120, "spd": 70, "spe": 100}},
	"ooze": {"name": "Ooze", "types": ["Poison"], "baseStats": {"hp": 70, "atk": 70, "def": 70, "spa": 70, "spd": 70, "spe": 70}},
	"tank": {"name": "Tank", "types": ["Steel"], "baseStats": {"hp": 100, "atk": 100, "def": 100, "spa": 60, "spd": 100, "spe": 50}},
}
const MOVES := {
	"jet": {"name": "Jet", "category": "Special", "type": "Water", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"kick": {"name": "Kick", "category": "Physical", "type": "Fighting", "basePower": 60, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"zap": {"name": "Zap", "category": "Status", "type": "Electric", "basePower": 0, "accuracy": 100, "pp": 20, "priority": 0, "flags": {}, "target": "normal", "status": "par"},
	"recover": {"name": "Recover", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 5, "priority": 0, "flags": {}, "target": "self", "heal": [1, 2]},
}
const TYPES := {
	"water": {"damageTaken": {"Water": 2}},
	"fire": {"damageTaken": {"Water": 1}},
}


## Plays one intent on its tick and nothing otherwise.
class Scripted extends RefCounted:
	var plan := {}

	func decide(battle: Battle, _side: int) -> Dictionary:
		return plan.get(battle.tick, {})


func _data() -> BattleData:
	return BattleData.new(SPECIES, MOVES, TYPES)


func _battle(items: Array, moves_a := ["kick", "jet"], plan_a := {}, species := ["squirt", "squirt"]) -> Battle:
	var spec := {"seed": 1, "arena": "stadium", "fighters": [
		{"species": species[0], "moves": moves_a, "item": items[0]},
		{"species": species[1], "moves": ["jet"], "item": items[1]}]}
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


func _moves(ids: Array) -> Array:
	return ids.map(func(id: String) -> BattleMove: return _data().convert_move(id).move)


func _run(battle: Battle, ticks: int) -> void:
	for i in ticks:
		battle.step()


func _items_shown(battle: Battle, side: int) -> Array:
	return battle.events.filter(func(e: Dictionary) -> bool: return e.type == "item" and e.side == side) \
		.map(func(e: Dictionary) -> String: return e.item)


func test_the_standard_item_follows_the_policy() -> void:
	var data := _data()
	assert_eq(Items.standard(SPECIES.tadpole, _moves(["jet"]), data), "eviolite", "can still evolve")
	assert_eq(Items.standard(SPECIES.squirt, _moves(["jet", "kick"]), data), "assaultvest", "bulky, no status moves")
	assert_eq(Items.standard(SPECIES.squirt, _moves(["jet", "zap"]), data), "leftovers", "a status move rules out the vest")
	assert_eq(Items.standard(SPECIES.cannon, _moves(["jet", "zap"]), data), "lifeorb", "a frail attacker")
	assert_eq(Items.standard(SPECIES.wall, _moves(["jet", "zap"]), data), "rockyhelmet", "physically sturdy")
	assert_eq(Items.standard(SPECIES.tank, _moves(["jet", "zap"]), data), "sitrusberry", "plenty of HP")
	assert_eq(Items.standard(SPECIES.ooze, _moves(["jet", "zap"]), data), "blacksludge", "a Poison type")
	var created := Battle.create({"seed": 1, "fighters": [{"species": "tadpole", "moves": ["jet"]}, {"species": "squirt", "moves": ["jet"]}]},
		data, [Scripted.new(), Scripted.new()])
	assert_eq(created.battle.fighters[0].item, "eviolite", "a spec without one gets the standard item")


func test_every_table_entry_is_a_known_effect() -> void:
	var keys := ["name", "heal_per_second", "needs_type", "heal_from_damage", "power", "hit_cost", "super_effective_power",
		"physical_power", "special_power", "stat_factors", "no_status_moves", "needs_evolution", "contact_damage",
		"focus_sash", "berry_heal", "berry_below", "cures_status", "type_power"]
	for id: String in Items.table():
		assert_eq(id, BattleData.to_id(Items.display_name(id)), "%s is keyed by its Showdown ID" % id)
		for key: String in Items.table()[id]:
			assert_true(key in keys, "%s: unknown effect '%s'" % [id, key])


func test_a_spec_can_name_an_item_or_none_but_not_an_unknown_one() -> void:
	var battle := _battle(["", "lifeorb"])
	assert_eq(battle.fighters[0].item, "")
	assert_eq(battle.fighters[1].item, "lifeorb")
	var spec := {"seed": 1, "fighters": [{"species": "squirt", "moves": ["jet"], "item": "choiceband"}, {"species": "squirt", "moves": ["jet"]}]}
	assert_true(Battle.create(spec, _data(), [Scripted.new(), Scripted.new()]).has("error"))


func test_damage_and_stat_items() -> void:
	var battle := _battle(["", ""])
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	var jet: BattleMove = _data().convert_move("jet").move
	var base: float = Battle.damage_parts(a, b, jet, _data()).factor
	for case: Array in [["lifeorb", 1.3], ["mysticwater", 1.2], ["wiseglasses", 1.1], ["muscleband", 1.0], ["charcoal", 1.0]]:
		a.set_item(case[0])
		assert_almost_eq(Battle.damage_parts(a, b, jet, _data()).factor / base, case[1], 1e-6, case[0])
	a.set_item("expertbelt")
	assert_almost_eq(Items.power_factor(a, jet, 2.0), 1.2, 1e-6, "Expert Belt on a super-effective hit")
	var spd: float = b.stat("spd")
	b.set_item("assaultvest")
	assert_almost_eq(b.stat("spd"), spd * 1.5, 1e-6)
	b.set_item("eviolite")
	assert_almost_eq(b.stat("def"), b.stats.def, 1e-6, "Eviolite does nothing for a species that can't evolve")
	b.can_evolve = true
	assert_almost_eq(b.stat("def"), b.stats.def * 1.5, 1e-6)


func test_the_assault_vest_forbids_status_moves() -> void:
	var battle := _battle(["assaultvest", ""], ["jet", "zap"], {0: {"use": 1}})
	assert_false(battle.fighters[0].move_ready(1))
	_run(battle, 30)
	assert_eq(battle.fighters[1].status, "")


func test_leftovers_heal_and_black_sludge_hurts_the_wrong_type() -> void:
	var battle := _battle(["leftovers", "blacksludge"])
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	a.hp = a.max_hp / 2
	var a_hp := a.hp
	var b_hp := b.hp
	_run(battle, 61)
	assert_eq(a.hp, a_hp + 3 * roundi(a.max_hp * 0.0125), "Leftovers, once a second")
	assert_true(b.hp < b_hp, "Black Sludge on a Water type")
	assert_true(battle.events.any(func(e: Dictionary) -> bool: return e.type == "regen"))
	assert_false(battle.events.any(func(e: Dictionary) -> bool: return e.type == "heal"), "steady healing isn't called out")


func test_life_orb_costs_hp_per_hit_and_rocky_helmet_hits_back() -> void:
	var battle := _battle(["lifeorb", "rockyhelmet"], ["kick"], {0: {"use": 0}})
	var a := battle.fighters[0]
	_run(battle, 15)
	var costs := battle.events.filter(func(e: Dictionary) -> bool: return e.type == "item_damage" and e.side == 0)
	assert_eq(costs.size(), 2, "Life Orb's cost and the helmet")
	assert_eq(a.hp, a.max_hp - roundi(a.max_hp * 0.006) - roundi(a.max_hp * 0.03))
	assert_true("rockyhelmet" in _items_shown(battle, 1))


func test_focus_sash_and_sitrus_berry_are_used_once() -> void:
	var battle := _battle(["", "focussash"], ["kick"], {0: {"use": 0}})
	var b := battle.fighters[1]
	b.max_hp = 2
	b.hp = 2
	_run(battle, 15)
	assert_eq(b.hp, 1, "the sash holds from full HP")
	assert_true(b.item_used)
	battle = _battle(["", "sitrusberry"], ["kick"], {0: {"use": 0}})
	b = battle.fighters[1]
	b.hp = b.max_hp / 2 + 1
	_run(battle, 15)
	assert_true(b.item_used, "eaten at half HP")
	assert_true(b.hp > b.max_hp / 2, "and it healed")
	assert_true("sitrusberry" in _items_shown(battle, 1))


func test_lum_berry_cures_the_first_status() -> void:
	var battle := _battle(["", "lumberry"], ["zap"], {0: {"use": 0}})
	_run(battle, 40)
	assert_eq(battle.fighters[1].status, "", "cured")
	assert_true(battle.fighters[1].item_used)
	battle._inflict(battle.fighters[1], "brn")
	assert_eq(battle.fighters[1].status, "brn", "only once")


func test_item_use_is_in_the_checksum() -> void:
	var plain := _battle(["sitrusberry", ""])
	var eaten := _battle(["sitrusberry", ""])
	eaten.fighters[0].item_used = true
	for each: Battle in [plain, eaten]:
		each.step()
		each.fighters[1].hp = 0
		each.step()
	assert_true(plain.checksum() != eaten.checksum())
