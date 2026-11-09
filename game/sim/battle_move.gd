class_name BattleMove
extends RefCounted
## A move as the real-time rules use it, derived from Showdown's move data (concepts_brief.md §9.3).
## Milestone 1 supports the melee and projectile kinds only.

enum Kind { MELEE, PROJECTILE }

var id: String
var name: String
var kind: Kind
var type: String
var physical: bool
var power: int
var windup_ticks: int
var recovery_ticks: int
var cooldown_ticks: int
var projectile_speed: float


## Returns {"move": BattleMove} or {"error": String} for moves milestone 1 can't play.
static func from_showdown(id: String, data: Dictionary) -> Dictionary:
	if data.get("category", "Status") == "Status" or int(data.get("basePower", 0)) <= 0:
		return {"error": "%s is a status or fixed-damage move, not supported yet" % id}
	if data.has("multihit") or data.get("flags", {}).has("charge") or data.get("flags", {}).has("recharge"):
		return {"error": "%s is a multi-hit, charge or recharge move, not supported yet" % id}
	if data.get("target", "normal") != "normal":
		return {"error": "%s targets an area, not supported yet" % id}
	var move := BattleMove.new()
	move.id = id
	move.name = data.get("name", id)
	move.kind = Kind.MELEE if data.get("flags", {}).has("contact") else Kind.PROJECTILE
	move.type = data.get("type", "Normal")
	move.physical = data.get("category") == "Physical"
	move.power = int(data.basePower)
	var melee := move.kind == Kind.MELEE
	var windup := Rules.MELEE_WINDUP if melee else Rules.PROJECTILE_WINDUP
	if int(data.get("priority", 0)) > 0:
		windup *= Rules.PRIORITY_WINDUP_FACTOR
	move.windup_ticks = Rules.seconds_to_ticks(windup)
	move.recovery_ticks = Rules.seconds_to_ticks(Rules.MELEE_RECOVERY if melee else Rules.PROJECTILE_RECOVERY)
	move.cooldown_ticks = Rules.seconds_to_ticks(Rules.cooldown_seconds(move.power, int(data.get("pp", 10))))
	move.projectile_speed = Rules.projectile_speed(data.get("accuracy", 100))
	return {"move": move}


func reach() -> float:
	return Rules.MELEE_REACH if kind == Kind.MELEE else Rules.PROJECTILE_RANGE
