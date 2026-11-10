class_name Fighter
extends RefCounted
## One side's state in the simulation. Positions are on the arena floor (x, z) in metres.

enum Action { READY, WINDUP, RECOVERY, DODGE }

const DEFAULT_RADIUS := 0.5
## Major statuses, indexed for the battle checksum.
const STATUS_CODES: Array[String] = ["", "brn", "par", "psn", "tox", "slp", "frz"]

var side: int
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
var action := Action.READY
var action_ticks := 0
var action_move := -1
var dodge_charges := Rules.DODGE_CHARGES
var dodge_recharge_ticks := 0
var dodge_recharge_total := 0
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
## Multi-hit strikes still to come: {"ticks": int, "move": index, "last": bool}.
var followups: Array[Dictionary] = []


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
	fighter.move_speed = Rules.move_speed(fighter.stats.spe)
	fighter.dodge_recharge_total = Rules.seconds_to_ticks(Rules.dodge_recharge_seconds(fighter.stats.spe))
	fighter.moves = battle_moves
	fighter.cooldowns.resize(battle_moves.size())
	return fighter


func is_fainted() -> bool:
	return hp <= 0


func can_act() -> bool:
	return action == Action.READY and not is_fainted() and not is_incapacitated()


## A stat after stat stages (and burn for Attack).
func stat(name: String) -> float:
	var value: float = stats[name] * Rules.stage_multiplier(boosts[name])
	if name == "atk" and status == "brn":
		value *= Rules.BURN_ATTACK_FACTOR
	return value


## Walking speed after Speed stages and paralysis.
func current_move_speed() -> float:
	var speed := move_speed * Rules.stage_multiplier(boosts.spe)
	return speed * (Rules.PARALYSIS_SPEED_FACTOR if status == "par" else 1.0)


## Asleep, frozen or stunned: can't act or move.
func is_incapacitated() -> bool:
	return status == "slp" or status == "frz" or stun_ticks > 0


## While dodging a fighter can't be hit.
func is_invulnerable() -> bool:
	return action == Action.DODGE


func can_dodge() -> bool:
	return can_act() and dodge_charges > 0


func move_ready(index: int) -> bool:
	return index >= 0 and index < moves.size() and cooldowns[index] == 0
