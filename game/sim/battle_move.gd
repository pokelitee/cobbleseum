class_name BattleMove
extends RefCounted
## A move as the real-time rules use it, derived from Showdown's move data (concepts_brief.md §9.3).
##
## Kinds so far:
## - MELEE and PROJECTILE: damaging moves, with any drain, recoil, self stat changes and
##   secondary effects (status, confusion, stat changes) from the data;
## - SELF_BUFF and HEAL: status moves the user aims at itself, applied on release;
## - DEBUFF and STATUS: status moves fired at the opponent as projectiles, lowering its stats
##   or inflicting a status condition or confusion.

enum Kind { MELEE, PROJECTILE, SELF_BUFF, DEBUFF, HEAL, STATUS }

## Showdown targets that mean "one opponent" in a one-on-one battle.
const SINGLE_TARGETS: Array[String] = ["normal", "any", "adjacentFoe", "randomNormal"]
## Status moves may also target every adjacent foe, which is just the one opponent.
const FOE_TARGETS: Array[String] = ["normal", "any", "adjacentFoe", "randomNormal", "allAdjacentFoes"]
const SELF_TARGETS: Array[String] = ["self", "adjacentAllyOrSelf"]
const STATS: Array[String] = ["atk", "def", "spa", "spd", "spe"]
const STATUSES: Array[String] = ["brn", "par", "psn", "tox", "slp", "frz"]
## Status moves whose real behaviour lives in Showdown's code (an HP cost, a charge turn,
## fainting the user, a gender check), so their data alone would play wrong.
const EXCLUDED: Array[String] = ["clangoroussoul", "filletaway", "geomancy", "memento", "captivate"]
## Heal amounts Showdown computes in code, as [numerator, denominator] of max HP.
const HEAL_OVERRIDES := {"morningsun": [1, 2], "synthesis": [1, 2], "moonlight": [1, 2], "shoreup": [1, 2]}

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
## Stat stages this move changes on its target (debuffs) or user (self-buffs).
var boosts: Dictionary = {}
## Stat stages a damaging move changes on its user when it hits (Close Combat, Draco Meteor).
var self_boosts: Dictionary = {}
## Major status ("brn", ...) or "" for STATUS moves; `confuses` for confusion.
var status := ""
var confuses := false
## Shares of max HP healed (HEAL), of damage dealt healed (drain) or taken back (recoil).
var heal_share := 0.0
var drain_share := 0.0
var recoil_share := 0.0
## Secondary effects rolled on hit: {"chance": 0-100, "status"?, "confuses"?, "boosts"?, "self_boosts"?}.
var secondaries: Array[Dictionary] = []


## Returns {"move": BattleMove} or {"error": String} for moves the rules can't play yet.
static func from_showdown(id: String, data: Dictionary) -> Dictionary:
	var move := BattleMove.new()
	move.id = id
	move.name = data.get("name", id)
	move.type = data.get("type", "Normal")
	move.physical = data.get("category") == "Physical"
	move.power = int(data.get("basePower", 0))
	var target: String = data.get("target", "normal")
	var flags: Dictionary = data.get("flags", {})
	var priority := int(data.get("priority", 0))
	var pp := int(data.get("pp", 10))
	if data.get("category", "Status") == "Status":
		var classified := _classify_status_move(id, data, move)
		if not classified.is_empty():
			return {"error": classified}
		var windup := Rules.STATUS_MOVE_WINDUP * (Rules.PRIORITY_WINDUP_FACTOR if priority > 0 else 1.0)
		move.windup_ticks = Rules.seconds_to_ticks(windup)
		move.recovery_ticks = Rules.seconds_to_ticks(Rules.STATUS_MOVE_RECOVERY)
		move.cooldown_ticks = Rules.seconds_to_ticks(Rules.status_move_cooldown_seconds(pp))
		move.projectile_speed = Rules.projectile_speed(data.get("accuracy", 100))
		return {"move": move}

	if move.power <= 0:
		return {"error": "%s is a fixed-damage move, not supported yet" % id}
	if data.has("multihit") or flags.has("charge") or flags.has("recharge"):
		return {"error": "%s is a multi-hit, charge or recharge move, not supported yet" % id}
	if not target in SINGLE_TARGETS:
		return {"error": "%s targets an area, not supported yet" % id}
	move.kind = Kind.MELEE if flags.has("contact") else Kind.PROJECTILE
	move.drain_share = _share(data.get("drain"))
	move.recoil_share = _share(data.get("recoil"))
	move.self_boosts = _stat_changes(data.get("self", {}).get("boosts", data.get("selfBoost", {}).get("boosts", {})))
	var secondaries: Array = data.get("secondaries", [])
	if data.get("secondary") is Dictionary:
		secondaries = [data.secondary]
	for raw: Variant in secondaries:
		if not raw is Dictionary:
			continue
		var effect := {"chance": int(raw.get("chance", 100))}
		if raw.get("status", "") in STATUSES:
			effect.status = raw.status
		if raw.get("volatileStatus", "") == "confusion":
			effect.confuses = true
		var target_boosts := _stat_changes(raw.get("boosts", {}))
		if not target_boosts.is_empty():
			effect.boosts = target_boosts
		var user_boosts := _stat_changes(raw.get("self", {}).get("boosts", {}))
		if not user_boosts.is_empty():
			effect.self_boosts = user_boosts
		if effect.size() > 1:
			move.secondaries.append(effect)
	var melee := move.kind == Kind.MELEE
	var windup := Rules.MELEE_WINDUP if melee else Rules.PROJECTILE_WINDUP
	if priority > 0:
		windup *= Rules.PRIORITY_WINDUP_FACTOR
	move.windup_ticks = Rules.seconds_to_ticks(windup)
	move.recovery_ticks = Rules.seconds_to_ticks(Rules.MELEE_RECOVERY if melee else Rules.PROJECTILE_RECOVERY)
	move.cooldown_ticks = Rules.seconds_to_ticks(Rules.cooldown_seconds(move.power, pp))
	move.projectile_speed = Rules.projectile_speed(data.get("accuracy", 100))
	return {"move": move}


## Sets the kind and effect of a status-category move. Returns "" or why it isn't supported.
static func _classify_status_move(id: String, data: Dictionary, move: BattleMove) -> String:
	if id in EXCLUDED:
		return "%s needs move-specific code, not supported yet" % id
	var target: String = data.get("target", "normal")
	var raw_boosts: Dictionary = data.get("boosts", {})
	var boosts := _stat_changes(raw_boosts)
	var only_stats := boosts.size() == raw_boosts.size()
	if target in SELF_TARGETS:
		var heal: Variant = HEAL_OVERRIDES.get(id, data.get("heal"))
		if heal != null and raw_boosts.is_empty():
			move.kind = Kind.HEAL
			move.heal_share = _share(heal)
			return ""
		if not boosts.is_empty() and only_stats and boosts.values().all(func(v: int) -> bool: return v > 0) \
				and not data.has("volatileStatus") and not data.has("heal"):
			move.kind = Kind.SELF_BUFF
			move.boosts = boosts
			return ""
	elif target in FOE_TARGETS and raw_boosts.is_empty():
		if data.get("status", "") in STATUSES:
			move.kind = Kind.STATUS
			move.status = data.status
			return ""
		if data.get("volatileStatus", "") == "confusion":
			move.kind = Kind.STATUS
			move.confuses = true
			return ""
	elif target in FOE_TARGETS and only_stats and boosts.values().all(func(v: int) -> bool: return v < 0) \
			and not data.has("status") and not data.has("volatileStatus"):
		move.kind = Kind.DEBUFF
		move.boosts = boosts
		return ""
	return "%s is a status move of a kind not supported yet" % id


## Keeps the stat changes the rules model (no accuracy or evasion).
static func _stat_changes(raw: Variant) -> Dictionary:
	var changes := {}
	if raw is Dictionary:
		for stat: String in raw:
			if stat in STATS and int(raw[stat]) != 0:
				changes[stat] = int(raw[stat])
	return changes


static func _share(fraction: Variant) -> float:
	return float(fraction[0]) / float(fraction[1]) if fraction is Array and fraction.size() == 2 else 0.0


## True for kinds fired at the opponent as a projectile.
func is_projectile() -> bool:
	return kind in [Kind.PROJECTILE, Kind.DEBUFF, Kind.STATUS]


## True for kinds applied to the user.
func is_self() -> bool:
	return kind in [Kind.SELF_BUFF, Kind.HEAL]


func is_damaging() -> bool:
	return kind in [Kind.MELEE, Kind.PROJECTILE]


## The largest gap between hitboxes this move can be started from.
func reach() -> float:
	if kind == Kind.MELEE:
		return Rules.MELEE_DASH_RANGE
	if is_self():
		return INF
	return Rules.PROJECTILE_RANGE
