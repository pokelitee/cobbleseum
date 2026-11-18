extends TestCase
## Entry hazards (concepts_brief.md §9.11): laid on the foe's side, acting on its send-outs, until
## a spin, Defog or Tidy Up clears them.

const SPECIES := {
	"squirt": {"name": "Squirt", "types": ["Water"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}},
	"blaze": {"name": "Blaze", "types": ["Fire"], "baseStats": {"hp": 80, "atk": 115, "def": 75, "spa": 65, "spd": 75, "spe": 120}},
	"bird": {"name": "Bird", "types": ["Fire", "Flying"], "baseStats": {"hp": 80, "atk": 80, "def": 80, "spa": 80, "spd": 80, "spe": 80}},
	"sludge": {"name": "Sludge", "types": ["Poison"], "baseStats": {"hp": 80, "atk": 80, "def": 80, "spa": 80, "spd": 80, "spe": 80}},
}
const MOVES := {
	"jet": {"name": "Jet", "category": "Special", "type": "Water", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"stealthrock": {"name": "Stealth Rock", "category": "Status", "type": "Rock", "basePower": 0, "accuracy": true, "pp": 20, "priority": 0, "flags": {}, "target": "foeSide", "sideCondition": "stealthrock"},
	"spikes": {"name": "Spikes", "category": "Status", "type": "Ground", "basePower": 0, "accuracy": true, "pp": 20, "priority": 0, "flags": {}, "target": "foeSide", "sideCondition": "spikes"},
	"toxicspikes": {"name": "Toxic Spikes", "category": "Status", "type": "Poison", "basePower": 0, "accuracy": true, "pp": 20, "priority": 0, "flags": {}, "target": "foeSide", "sideCondition": "toxicspikes"},
	"stickyweb": {"name": "Sticky Web", "category": "Status", "type": "Bug", "basePower": 0, "accuracy": true, "pp": 20, "priority": 0, "flags": {}, "target": "foeSide", "sideCondition": "stickyweb"},
	"rapidspin": {"name": "Rapid Spin", "category": "Physical", "type": "Normal", "basePower": 50, "accuracy": 100, "pp": 40, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"defog": {"name": "Defog", "category": "Status", "type": "Flying", "basePower": 0, "accuracy": true, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
}
const TYPES := {
	"water": {"damageTaken": {"Fire": 2, "Water": 2, "Rock": 0}},
	"fire": {"damageTaken": {"Water": 1, "Fire": 2, "Rock": 1}},
	"flying": {"damageTaken": {"Rock": 1, "Ground": 3}},
	"poison": {"damageTaken": {"Poison": 2}},
}


class Scripted extends RefCounted:
	var plan := {}

	func decide(battle: Battle, _side: int) -> Dictionary:
		return plan.get(battle.tick, {})


func _battle(team_a: Array, team_b: Array, a := Scripted.new(), b := Scripted.new()) -> Battle:
	var spec := {"seed": 1, "arena": "stadium", "fighters": [{"team": team_a}, {"team": team_b}]}
	var created := Battle.create(spec, BattleData.new(SPECIES, MOVES, TYPES), [a, b])
	assert_false(created.has("error"), str(created.get("error", "")))
	return created.battle


func _member(species: String, moves := ["jet"]) -> Dictionary:
	return {"species": species, "moves": moves, "ability": "", "item": ""}


func _use(battle: Battle, script: Scripted, move: int) -> void:
	script.plan[battle.tick] = {"use": move}
	for i in 30:
		battle.step()


func _events(battle: Battle, type: String) -> Array:
	return battle.events.filter(func(e: Dictionary) -> bool: return e.type == type)


func test_hazards_are_laid_on_the_foe_s_side_and_stack_to_their_limit() -> void:
	var a := Scripted.new()
	var battle := _battle([_member("squirt", ["spikes", "stealthrock"])], [_member("blaze"), _member("squirt")], a)
	assert_eq(battle.conditions.bench[1], 1)
	for i in 4:
		_use(battle, a, 0)
		battle.fighters[0].cooldowns[0] = 0
	assert_eq(battle.conditions.hazards[1].spikes, 3, "Spikes stack to three layers")
	assert_eq(_events(battle, "hazard_failed").size(), 1, "a fourth fails")
	assert_true(battle.conditions.hazards[0].is_empty())


func test_stealth_rock_and_spikes_hurt_on_send_out_by_type_and_layers() -> void:
	var b := Scripted.new()
	var battle := _battle([_member("squirt")], [_member("squirt"), _member("blaze"), _member("bird")], Scripted.new(), b)
	battle.conditions.hazards[1] = {"stealthrock": 1, "spikes": 2}
	battle.step()
	b.plan[battle.tick] = {"switch": 1}
	battle.step()
	var blaze: Fighter = battle.teams[1][1]
	var rock := roundi(blaze.max_hp * ArenaConditions.ROCK_SHARE * 1.3)
	var spikes := roundi(blaze.max_hp * ArenaConditions.SPIKES_SHARES[2])
	assert_eq(blaze.max_hp - blaze.hp, rock + spikes, "Rock is super effective on Fire, compressed to x1.3")
	assert_eq(_events(battle, "hazard_damage").size(), 2)
	# A Flying type misses the Spikes but not the rocks.
	while battle.switch_cooldown(1) > 0 or battle.fighters[1].action != Fighter.Action.READY:
		battle.step()
	b.plan[battle.tick] = {"switch": 2}
	battle.step()
	var bird: Fighter = battle.teams[1][2]
	assert_eq(bird.max_hp - bird.hp, roundi(bird.max_hp * ArenaConditions.ROCK_SHARE * 1.6), "x4 weak: x1.6")


func test_toxic_spikes_poison_and_a_grounded_poison_type_absorbs_them() -> void:
	var b := Scripted.new()
	var battle := _battle([_member("squirt")], [_member("squirt"), _member("blaze"), _member("sludge")], Scripted.new(), b)
	battle.conditions.hazards[1] = {"toxicspikes": 2, "stickyweb": 1}
	battle.step()
	b.plan[battle.tick] = {"switch": 1}
	battle.step()
	assert_eq(battle.teams[1][1].status, "tox", "two layers poison badly")
	assert_eq(battle.teams[1][1].boosts.spe, -1, "Sticky Web")
	while battle.switch_cooldown(1) > 0 or battle.fighters[1].action != Fighter.Action.READY:
		battle.step()
	b.plan[battle.tick] = {"switch": 2}
	battle.step()
	assert_eq(battle.teams[1][2].status, "")
	assert_false(battle.conditions.hazards[1].has("toxicspikes"), "absorbed")


func test_spins_clear_their_side_and_defog_both() -> void:
	var a := Scripted.new()
	var battle := _battle([_member("squirt", ["rapidspin", "defog"])], [_member("blaze"), _member("squirt")], a)
	battle.conditions.hazards[0] = {"spikes": 1}
	battle.conditions.hazards[1] = {"stealthrock": 1}
	battle.fighters[0].position = Vector2(0, 0)
	battle.fighters[1].position = Vector2(0, 1.2)
	_use(battle, a, 0)
	assert_true(battle.conditions.hazards[0].is_empty(), "Rapid Spin clears its own side")
	assert_false(battle.conditions.hazards[1].is_empty())
	battle.conditions.hazards[0] = {"spikes": 1}
	battle.conditions.set_screen(1, "reflect", 100)
	_use(battle, a, 1)
	assert_true(battle.conditions.hazards[0].is_empty() and battle.conditions.hazards[1].is_empty(), "Defog clears both")
	assert_true(battle.conditions.screens[1].is_empty(), "and the foe's screens")


func test_laying_hazards_is_worth_more_with_more_foes_to_come() -> void:
	var conditions := ArenaConditions.new()
	var foe := Fighter.new()
	conditions.bench = PackedInt32Array([0, 0])
	assert_eq(conditions.hazard_value(1, "stealthrock", foe), 0.0, "no one left to send out")
	conditions.bench = PackedInt32Array([0, 5])
	assert_true(conditions.hazard_value(1, "stealthrock", foe) > 0.5)
	conditions.hazards[1] = {"stealthrock": 1}
	assert_eq(conditions.hazard_value(1, "stealthrock", foe), 0.0, "already up")
