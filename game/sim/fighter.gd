class_name Fighter
extends RefCounted
## One side's state in the simulation. Positions are on the arena floor (x, z) in metres.

## GUARD covers the guard's active window and then, if it blocked nothing, its recovery.
## SEND_OUT is a team member landing from its ball (Rules.SEND_OUT_SECONDS).
enum Action { READY, WINDUP, RECOVERY, DODGE, GUARD, SEND_OUT }

const DEFAULT_RADIUS := 0.5
## Major statuses, indexed for the battle checksum.
const STATUS_CODES: Array[String] = ["", "brn", "par", "psn", "tox", "slp", "frz"]

var side: int
## Its place in its side's team (Battle.teams), 0 for the first.
var slot := 0
## Doubles (M17): its place on the field, 0 or 1 (always 0 in singles), and the place of the foe
## it's locked onto (Battle.target_of).
var place := 0
var target_place := 0
## Doubles' ally moves: ticks left on Helping Hand's boost (waiting for its next damaging move)
## and on Dragon Cheer's, and whether the move it's using now is helped.
var helping_ticks := 0
var cheer_ticks := 0
var helped := false
## Doubles: its ally out (Battle._link_allies), for Friend Guard; null in singles.
var ally: Fighter = null
## Landing from its ball after a knockout: it can't be hit until it lands.
var shielded := false
var species_id: String
var name: String
var types: Array
var stats: Dictionary
var max_hp: int
var hp: int
var radius: float
var move_speed: float
var moves: Array[BattleMove] = []
var cooldowns: PackedInt32Array = []
var position := Vector2.ZERO
var facing := Vector2.UP
## Metres per second: walking (with acceleration), knockback and the slide out of a dodge.
var velocity := Vector2.ZERO
var weight_kg := Rules.KNOCKBACK_REFERENCE_KG
## Scales acceleration and turning (Rules.agility); flying types glide (brake gently).
var agility := 1.0
var glides := false
## The ground height under the fighter (Terrain), and how high it can step up.
var ground := 0.0
var climb := Rules.CLIMB
var action := Action.READY
var action_ticks := 0
var action_move := -1
var dodge_charges := Rules.DODGE_CHARGES
var dodge_recharge_ticks := 0
var dodge_recharge_total := 0
## Ticks until the fighter can feint again, and whether its wind-up is a feint. Opponents'
## controllers must not read `feinting`: a feint looks like any other wind-up.
var feint_cooldown := 0
var feinting := false
## Ticks until the fighter can guard again, and whether its current guard has blocked a hit.
var guard_cooldown := 0
var guard_blocked := false
## Per-tick dash while dodging.
var dodge_step := Vector2.ZERO
## Stat stages, -6 to +6, and ticks since they last changed (for decay).
var boosts := {"atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0}
var stage_ticks := 0
## Major status condition ("brn", "par", "psn", "tox", "slp", "frz") or "", with ticks left.
var status := ""
var status_ticks := 0
## Bad poison's rising level.
var toxic_level := 0
var confusion_ticks := 0
## Paralysis stuns.
var stun_ticks := 0
## The ability's Showdown ID ("" for none) and its entry in Abilities' table.
var ability := ""
var ability_effect := {}
## Ability state: ticks left on Flash Fire's boost, until Intimidate strikes again, until
## Speed Boost's next raise and until Weak Armor can trigger again; whether Sturdy is spent.
var flash_fire_ticks := 0
var intimidate_ticks := 0
var speed_boost_ticks := 0
var weak_armor_ticks := 0
var sturdy_used := false
## The held item's Showdown ID ("" for none), its entry in Items' table, whether a
## one-use item (a berry, Focus Sash) is spent, and whether the species can still evolve
## (for Eviolite).
var item := ""
var item_effect := {}
var item_used := false
var can_evolve := false
## The arena conditions (weather) the battle shares with both fighters; stats read them.
var arena := ArenaConditions.new()
## Multi-hit strikes still to come: {"ticks": int, "move": index, "last": bool, "hit": int}.
var followups: Array[Dictionary] = []
## What just happened, for moves that follow it (rules version 37, MoveEffects): ticks left of
## Rules.RECENT_SECONDS since it was hit by a move, took any damage, missed, or had a stat
## lowered; hits taken all battle (Rage Fist); ticks since it last came out; the moves it has used
## since (Last Resort); and its run of one growing move ({"move", "count", "ticks"}, Fury Cutter).
var hit_ticks := 0
var hurt_ticks := 0
var missed_ticks := 0
var lowered_ticks := 0
var times_hit := 0
var out_ticks := 0
var used_moves := {}
var combo := {}
## Rules version 38: ticks left of Rules.RECENT_SECONDS since a stat of its rose (Alluring Voice);
## the hits it took in the last Rules.RETURN_SECONDS, newest last ({"ticks", "amount",
## "physical", and the attacker's "side" and "slot"}, Counter: indices, not the Fighter, so no
## reference cycle keeps fighters alive); and its Future Sight on the way ({"ticks", "move":
## index, "target": the foe's index in Battle.fighters}, {} for none), which lands even if it
## has been recalled since.
var raised_ticks := 0
var taken: Array[Dictionary] = []
var foresight := {}


static func create(side_index: int, species_id_value: String, species: Dictionary, battle_moves: Array[BattleMove], radius_metres: float) -> Fighter:
	var fighter := Fighter.new()
	fighter.side = side_index
	fighter.species_id = species_id_value
	fighter.name = species.get("name", species_id_value)
	fighter.types = species.get("types", ["Normal"])
	var base: Dictionary = species.baseStats
	fighter.stats = {
		"atk": Rules.stat(base.atk), "def": Rules.stat(base.def),
		"spa": Rules.stat(base.spa), "spd": Rules.stat(base.spd), "spe": Rules.stat(base.spe),
	}
	fighter.max_hp = roundi(Rules.hp_stat(base.hp) * Rules.HP_MULTIPLIER)
	fighter.hp = fighter.max_hp
	fighter.radius = radius_metres
	fighter.weight_kg = float(species.get("weightkg", Rules.KNOCKBACK_REFERENCE_KG))
	fighter.agility = Rules.agility(fighter.stats.spe, fighter.weight_kg)
	fighter.glides = "Flying" in fighter.types
	fighter.climb = Rules.FLY_CLIMB if fighter.glides else Rules.CLIMB
	fighter.move_speed = Rules.move_speed(fighter.stats.spe)
	fighter.dodge_recharge_total = Rules.seconds_to_ticks(Rules.dodge_recharge_seconds(fighter.stats.spe))
	fighter.moves = battle_moves
	fighter.cooldowns.resize(battle_moves.size())
	return fighter


func is_knocked_out() -> bool:
	return hp <= 0


func can_act() -> bool:
	return action == Action.READY and not is_knocked_out() and not is_incapacitated()


## A stat after stat stages, the ability, the item, the weather, and burn for Attack.
func stat(name: String) -> float:
	var value: float = stats[name] * Rules.stage_multiplier(boosts[name]) * Abilities.stat_factor(self, name) * Items.stat_factor(self, name) 		* arena.stat_factor(self, name)
	if name == "atk" and status == "brn" and not ability_effect.get("ignores_burn", false):
		value *= Rules.BURN_ATTACK_FACTOR
	return value


## Walking speed after Speed stages, the ability, Tailwind and paralysis; under Trick Room, from
## the Speed stat mirrored (Rules.mirrored_speed), then paralysis.
func current_move_speed() -> float:
	var speed := move_speed * Rules.stage_multiplier(boosts.spe) * Abilities.stat_factor(self, "spe") * arena.speed_factor(self)
	if arena.field.has("trickroom"):
		speed = Rules.move_speed(Rules.mirrored_speed(stat("spe")))
	var slowed: bool = status == "par" and not ability_effect.get("ignores_paralysis", false)
	return speed * (Rules.PARALYSIS_SPEED_FACTOR if slowed else 1.0)


## Agility (acceleration and turning) now: from the mirrored Speed stat under Trick Room.
func current_agility() -> float:
	if arena.field.has("trickroom"):
		return Rules.agility(Rules.mirrored_speed(stat("spe")), weight_kg)
	return agility


## Ticks a dodge charge takes to recharge now: from the mirrored Speed stat under Trick Room.
func dodge_recharge_needed() -> int:
	if arena.field.has("trickroom"):
		return Rules.seconds_to_ticks(Rules.dodge_recharge_seconds(Rules.mirrored_speed(stat("spe"))))
	return dodge_recharge_total


## How high the fighter can step up now: Gravity holds fliers to the ground's step.
func step_height() -> float:
	return Rules.CLIMB if arena.field.has("gravity") else climb


## Asleep, frozen or stunned: can't act or move.
func is_incapacitated() -> bool:
	return status == "slp" or status == "frz" or stun_ticks > 0


## While dodging, or landing shielded after a knockout, a fighter can't be hit.
func is_invulnerable() -> bool:
	return action == Action.DODGE or (action == Action.SEND_OUT and shielded)


func can_dodge() -> bool:
	return can_act() and dodge_charges > 0


func move_ready(index: int) -> bool:
	return index >= 0 and index < moves.size() and cooldowns[index] == 0 and not Items.forbids(self, moves[index]) \
		and arena.usable(self, moves[index])


## Whether move `index` can be feinted now: a ready melee or area move, feints off cooldown.
func can_feint(index: int) -> bool:
	return can_act() and feint_cooldown == 0 and move_ready(index) and moves[index].can_feint()


func can_guard() -> bool:
	return can_act() and guard_cooldown == 0


## Whether the guard is up (its active window, not the recovery after a whiff).
func is_guarding() -> bool:
	return action == Action.GUARD and action_ticks > Rules.seconds_to_ticks(Rules.GUARD_RECOVERY)


## Whether a hit coming from `direction` (pointing from the fighter toward the hit's source)
## meets the guard.
func guards_against(direction: Vector2) -> bool:
	return is_guarding() and facing.dot(direction.normalized()) >= cos(deg_to_rad(Rules.GUARD_ARC)) - 1e-6


## Gives the fighter an ability (a Showdown ID in Abilities' table, or "" for none).
func set_ability(id: String) -> void:
	ability = id
	ability_effect = Abilities.effect(id)


## Ticks to wind up `move`: Prankster speeds up status moves like priority (heals stay a
## channel), and sun skips Solar Beam's charge.
func windup_ticks(move: BattleMove) -> int:
	if ability_effect.get("prankster", false) and not move.is_damaging() and move.kind != BattleMove.Kind.HEAL:
		return Rules.seconds_to_ticks(Rules.STATUS_MOVE_WINDUP * Rules.PRIORITY_WINDUP_FACTOR)
	return arena.windup_ticks(self, move, move.windup_ticks)


## Gives the fighter a held item (a Showdown ID in Items' table, or "" for none).
func set_item(id: String) -> void:
	item = id
	item_effect = Items.effect(id)
	item_used = false
