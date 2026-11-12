class_name BattleMove
extends RefCounted
## A move as the real-time rules use it, derived from Showdown's move data (concepts_brief.md §9.3).
##
## Kinds so far:
## - MELEE, PROJECTILE and AREA (a blast around the user): damaging moves, with any drain,
##   recoil, self stat changes and secondary effects (status, confusion, stat changes) from
##   the data. Any of them can also hit several times, charge (a longer wind-up) or need to
##   recharge (a longer recovery); fixed-damage moves deal a set amount;
## - SELF_BUFF and HEAL: status moves the user aims at itself, applied on release (a heal is a
##   long channel that any hit cancels);
## - DEBUFF and STATUS: status moves fired at the opponent as projectiles, lowering its stats
##   or inflicting a status condition or confusion.

enum Kind { MELEE, PROJECTILE, SELF_BUFF, DEBUFF, HEAL, STATUS, AREA }

## Showdown targets that mean "one opponent" in a one-on-one battle.
const SINGLE_TARGETS: Array[String] = ["normal", "any", "adjacentFoe", "randomNormal"]
## Damaging moves that hit everything around the user.
const AREA_TARGETS: Array[String] = ["allAdjacent", "allAdjacentFoes"]
## Status moves may also target every adjacent foe, which is just the one opponent.
const FOE_TARGETS: Array[String] = ["normal", "any", "adjacentFoe", "randomNormal", "allAdjacentFoes"]
const SELF_TARGETS: Array[String] = ["self", "adjacentAllyOrSelf"]
const STATS: Array[String] = ["atk", "def", "spa", "spd", "spe"]
const STATUSES: Array[String] = ["brn", "par", "psn", "tox", "slp", "frz"]
## Status moves whose real behaviour lives in Showdown's code (an HP cost, a charge turn,
## knocking out the user, a gender check), so their data alone would play wrong.
const EXCLUDED: Array[String] = ["clangoroussoul", "filletaway", "geomancy", "memento", "captivate"]
## Damaging moves whose condition or cost lives in Showdown's code, so they'd play as free
## strong hits: Focus Punch fails if the user is hit, Last Resort needs its other moves used
## first, Future Sight and Doom Desire land later, Dream Eater needs a sleeping target,
## Synchronoise a shared type, Belch a berry; Steel Beam and Mind Blown cost half the user's
## HP; Shell Trap and Beak Blast need the user hit first; Water Spout, Eruption and Dragon
## Energy lose power as the user's HP falls; Steel Roller needs a terrain and Poltergeist a
## held item.
const DAMAGING_EXCLUDED: Array[String] = ["focuspunch", "lastresort", "futuresight", "doomdesire", "dreameater",
	"synchronoise", "belch", "steelbeam", "mindblown", "shelltrap", "beakblast", "waterspout", "eruption",
	"dragonenergy", "steelroller", "poltergeist"]
## Heal amounts Showdown computes in code, as [numerator, denominator] of max HP.
const HEAL_OVERRIDES := {"morningsun": [1, 2], "synthesis": [1, 2], "moonlight": [1, 2], "shoreup": [1, 2]}

var id: String
var name: String
var kind: Kind
var type: String
var physical: bool
## The stats damage is computed from: Attack/Defense or Special Attack/Special Defense, unless
## Showdown's data overrides them (Body Press attacks with Defense, Psyshock hits Defense,
## Foul Play uses the target's Attack: `target_attacks`).
var offensive_stat := "atk"
var defensive_stat := "def"
var target_attacks := false
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
## Hits per use: a fixed count, or 2-5 rolled with Rules.MULTI_HIT_WEIGHTS.
var hits_min := 1
var hits_max := 1
var charges := false
var recharges := false
## Damage that ignores stats and type (Seismic Toss); 0 for none. Not scaled by
## Rules.HP_MULTIPLIER, like every other move's damage, so it keeps its main-series balance
## against them.
var fixed_damage := 0
## The user is knocked out after using it (Explosion).
var self_destructs := false
## Secondary effects rolled on hit: {"chance": 0-100, "status"?, "confuses"?, "boosts"?, "self_boosts"?}.
var secondaries: Array[Dictionary] = []


## The attacking stat this move's damage uses, after stages (and burn for Attack).
func attack_stat(attacker: Fighter, defender: Fighter) -> float:
	return (defender if target_attacks else attacker).stat(offensive_stat)


## Stages the user's own drop takes off the stat its damage comes from (Draco Meteor: -2), as a
## negative number; 0 for none.
func own_stat_drop() -> int:
	return mini(0, int(self_boosts.get(offensive_stat, 0))) if not target_attacks else 0


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
		if move.kind == Kind.HEAL:
			windup = Rules.HEAL_WINDUP
			move.heal_share *= Rules.HEAL_FACTOR
		move.windup_ticks = Rules.seconds_to_ticks(windup)
		move.recovery_ticks = Rules.seconds_to_ticks(Rules.STATUS_MOVE_RECOVERY)
		move.cooldown_ticks = Rules.seconds_to_ticks(Rules.status_move_cooldown_seconds(pp))
		move.projectile_speed = Rules.projectile_speed(data.get("accuracy", 100))
		return {"move": move}

	if id in DAMAGING_EXCLUDED:
		return {"error": "%s needs move-specific code, not supported yet" % id}
	var fixed: Variant = data.get("damage")
	if fixed is String and fixed == "level":
		move.fixed_damage = Rules.LEVEL
	elif fixed is float or fixed is int:
		move.fixed_damage = int(fixed)
	if move.power <= 0 and move.fixed_damage == 0:
		return {"error": "%s computes its power in code, not supported yet" % id}
	if target in AREA_TARGETS:
		move.kind = Kind.AREA
	elif target in SINGLE_TARGETS:
		move.kind = Kind.MELEE if flags.has("contact") else Kind.PROJECTILE
	else:
		return {"error": "%s has target '%s', not supported yet" % [id, target]}
	var multihit: Variant = data.get("multihit")
	if multihit is Array and multihit.size() == 2:
		move.hits_min = int(multihit[0])
		move.hits_max = int(multihit[1])
	elif multihit != null:
		move.hits_min = int(multihit)
		move.hits_max = int(multihit)
	move.charges = flags.has("charge")
	move.recharges = flags.has("recharge")
	move.self_destructs = data.get("selfdestruct") == "always"
	move.drain_share = _share(data.get("drain"))
	move.recoil_share = _share(data.get("recoil"))
	move.self_boosts = _stat_changes(data.get("self", {}).get("boosts", data.get("selfBoost", {}).get("boosts", {})))
	move.offensive_stat = data.get("overrideOffensiveStat", "atk" if move.physical else "spa")
	move.defensive_stat = data.get("overrideDefensiveStat", "def" if move.physical else "spd")
	move.target_attacks = data.get("overrideOffensivePokemon") == "target"
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
	var windup: float = {Kind.MELEE: Rules.MELEE_WINDUP, Kind.PROJECTILE: Rules.PROJECTILE_WINDUP, Kind.AREA: Rules.AREA_WINDUP}[move.kind]
	var recovery: float = {Kind.MELEE: Rules.MELEE_RECOVERY, Kind.PROJECTILE: Rules.PROJECTILE_RECOVERY, Kind.AREA: Rules.AREA_RECOVERY}[move.kind]
	if priority > 0:
		windup *= Rules.PRIORITY_WINDUP_FACTOR
	if move.charges:
		windup += Rules.CHARGE_EXTRA
	if move.recharges:
		recovery += Rules.RECHARGE_EXTRA
	# Follow-up hits land during the recovery.
	recovery += (move.hits_max - 1) * Rules.MULTI_HIT_INTERVAL
	move.windup_ticks = Rules.seconds_to_ticks(windup)
	move.recovery_ticks = Rules.seconds_to_ticks(recovery)
	# Multi-hit moves cool down by their total power, fixed damage like a typical attack.
	var power_for_cooldown := roundi(move.power * move.expected_hits()) if move.fixed_damage == 0 else Rules.FIXED_DAMAGE_POWER
	move.cooldown_ticks = Rules.seconds_to_ticks(Rules.cooldown_seconds(power_for_cooldown, pp))
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


# These run every tick, so they compare directly instead of building arrays.

## True for kinds fired at the opponent as a projectile.
func is_projectile() -> bool:
	return kind == Kind.PROJECTILE or kind == Kind.DEBUFF or kind == Kind.STATUS


## True for kinds applied to the user.
func is_self() -> bool:
	return kind == Kind.SELF_BUFF or kind == Kind.HEAL


func is_damaging() -> bool:
	return kind == Kind.MELEE or kind == Kind.PROJECTILE or kind == Kind.AREA


## Average hits per use.
func expected_hits() -> float:
	if hits_min == 2 and hits_max == 5:
		var total := 0.0
		for i in Rules.MULTI_HIT_WEIGHTS.size():
			total += (2 + i) * Rules.MULTI_HIT_WEIGHTS[i]
		return total
	return (hits_min + hits_max) / 2.0


## The largest gap between hitboxes this move can be started from.
func reach() -> float:
	if kind == Kind.MELEE:
		return Rules.MELEE_DASH_RANGE
	if kind == Kind.AREA:
		return Rules.AREA_RADIUS
	if is_self():
		return INF
	return Rules.PROJECTILE_RANGE
