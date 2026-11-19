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
##   or inflicting a status condition or confusion;
## - ARENA: arena moves (§9.11), applied on release like a self-buff, setting a weather, a
##   surge, a screen, a field or side condition (Trick Room, Tailwind, ...) or acting on the
##   whole field once (Haze, Court Change), or Wide Guard (M17);
## - ALLY and REDIRECT (M17, doubles): applied on release to the ally (boosts, Helping Hand,
##   Dragon Cheer; Howl the user too) or drawing the foes' attacks (Follow Me, Rage Powder).
##   Team heals are HEAL moves that heal the ally too.

enum Kind { MELEE, PROJECTILE, SELF_BUFF, DEBUFF, HEAL, STATUS, AREA, ARENA, ALLY, REDIRECT }

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
## strong hits: Future Sight and Doom Desire land later; Steel Beam and Mind Blown cost half the
## user's HP; Shell Trap and Beak Blast need the user hit first.
const DAMAGING_EXCLUDED: Array[String] = ["futuresight", "doomdesire", "steelbeam", "mindblown", "shelltrap", "beakblast"]
## Moves whose power Showdown works out in code (MoveEffects): the power the rules give them for
## cooldowns (their power in battle follows the state).
const CODE_POWER := {"reversal": 60, "flail": 60, "hardpress": 100, "crushgrip": 120, "wringout": 120, "grassknot": 60,
	"lowkick": 60, "heavyslam": 60, "heatcrash": 60, "gyroball": 60, "electroball": 60, "present": 60}
## Focus Punch is a channel like a heal: any hit cancels it.
const CHANNELLED: Array[String] = ["focuspunch"]
## Heal amounts Showdown computes in code, as [numerator, denominator] of max HP.
const HEAL_OVERRIDES := {"morningsun": [1, 2], "synthesis": [1, 2], "moonlight": [1, 2], "shoreup": [1, 2]}
## Doubles' ally moves (M17): what each does to the ally ("helping": Helping Hand, "cheer":
## Dragon Cheer, "": only its boosts), the team heals (shares of max HP, Jungle Healing's and Lunar
## Blessing's from Showdown's code, which also cure a status), and the redirecting moves.
const ALLY_MOVES := {"helpinghand": "helping", "dragoncheer": "cheer", "coaching": "", "aromaticmist": "", "howl": ""}
const TEAM_HEALS := {"lifedew": [1, 4], "junglehealing": [1, 4], "lunarblessing": [1, 4]}
const CURING_HEALS: Array[String] = ["junglehealing", "lunarblessing"]
const REDIRECTS: Array[String] = ["followme", "ragepowder"]

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
## Showdown's flags for the move (contact, punch, bite, sound, bullet, ...), for abilities.
var flags: Dictionary = {}
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
## The weather or surge an ARENA move sets ("rain", ...; ArenaConditions.WEATHERS and SURGES).
var weather := ""
var surge := ""
var screen := ""
## An entry hazard it lays on the foe's side (ArenaConditions.HAZARDS), and which sides' hazards
## it clears: "own", "both" or "".
var hazard := ""
var clears := ""
## The field or side condition it sets ("trickroom", "tailwind", ...), or "haze" or
## "courtchange" (ArenaConditions.FIELDS, SIDE_CONDITIONS and ONCE); "" for none.
var field_effect := ""
## Showdown's priority: above 0 winds up faster (Rules.PRIORITY_WINDUP_FACTOR).
var priority := 0
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
## Doubles (M17): which fighters a spread move reaches: "foes" (Showdown's allAdjacentFoes: every
## foe, and for status moves a projectile at each), "all" (allAdjacent: the ally too) or "" for a
## single-target move. Singles reads it as one opponent either way.
var spread := ""
## Doubles' ally moves: an ALLY move's effect on the ally ("helping", "cheer" or "") and whether
## it boosts the user too (Howl); a team heal (HEAL, healing the ally too) and whether it cures
## a status; Wide Guard (ARENA).
var ally_effect := ""
var with_user := false
var team_heal := false
var cures := false
var wide_guard := false
## A variant made by MoveEffects for the battle's state (another type or power): it isn't adapted
## again. Variants of this move, by "type|power".
var adapted := false
## A long wind-up that any hit cancels (heals and Focus Punch).
var channels := false
var _variants := {}


## This move with another type and power (MoveEffects), made once and kept.
func variant(new_type: String, new_power: int) -> BattleMove:
	var key := "%s|%d" % [new_type, new_power]
	if not _variants.has(key):
		var copy := BattleMove.new()
		for property in get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.name != "_variants":
				copy.set(property.name, get(property.name))
		copy.type = new_type
		copy.power = new_power
		copy.adapted = true
		_variants[key] = copy
	return _variants[key]


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
	move.clears = str(ArenaConditions.HAZARD_CLEARERS.get(id, ""))
	move.name = data.get("name", id)
	move.type = data.get("type", "Normal")
	move.physical = data.get("category") == "Physical"
	move.power = int(data.get("basePower", 0))
	var target: String = data.get("target", "normal")
	move.spread = {"allAdjacentFoes": "foes", "allAdjacent": "all"}.get(target, "")
	var flags: Dictionary = data.get("flags", {})
	move.flags = flags
	var priority := int(data.get("priority", 0))
	move.priority = priority
	var pp := int(data.get("pp", 10))
	if data.get("category", "Status") == "Status":
		var classified := _classify_status_move(id, data, move)
		if not classified.is_empty():
			return {"error": classified}
		var windup := Rules.STATUS_MOVE_WINDUP * (Rules.PRIORITY_WINDUP_FACTOR if priority > 0 else 1.0)
		if move.kind == Kind.HEAL:
			windup = Rules.HEAL_WINDUP
			move.heal_share *= Rules.HEAL_FACTOR
			move.channels = true
		move.windup_ticks = Rules.seconds_to_ticks(windup)
		move.recovery_ticks = Rules.seconds_to_ticks(Rules.STATUS_MOVE_RECOVERY)
		var cooldown := Rules.status_move_cooldown_seconds(pp)
		if move.kind == Kind.ARENA:
			cooldown = Rules.SCREEN_COOLDOWN if not move.screen.is_empty() else Rules.ARENA_MOVE_COOLDOWN
			if not move.hazard.is_empty():
				cooldown = Rules.HAZARD_COOLDOWN
			if move.wide_guard:
				cooldown = Rules.WIDE_GUARD_COOLDOWN
			if move.field_effect == "courtchange":
				cooldown = Rules.HAZARD_COOLDOWN
			elif move.field_effect == "haze":
				cooldown = Rules.status_move_cooldown_seconds(pp)
		if move.kind == Kind.REDIRECT:
			cooldown = Rules.REDIRECT_COOLDOWN
		move.cooldown_ticks = Rules.seconds_to_ticks(cooldown)
		move.projectile_speed = Rules.projectile_speed(data.get("accuracy", 100))
		return {"move": move}

	if id in DAMAGING_EXCLUDED:
		return {"error": "%s needs move-specific code, not supported yet" % id}
	move.power = int(CODE_POWER.get(id, move.power))
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
	if id in CHANNELLED:
		windup = Rules.HEAL_WINDUP
		move.channels = true
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
	if ALLY_MOVES.has(id):
		move.kind = Kind.ALLY
		move.ally_effect = ALLY_MOVES[id]
		move.boosts = _stat_changes(data.get("boosts", {}))
		move.with_user = data.get("target", "") == "allies"
		return ""
	if TEAM_HEALS.has(id):
		move.kind = Kind.HEAL
		move.team_heal = true
		move.heal_share = _share(TEAM_HEALS[id])
		move.cures = id in CURING_HEALS
		return ""
	if id in REDIRECTS:
		move.kind = Kind.REDIRECT
		return ""
	if id == "wideguard":
		move.kind = Kind.ARENA
		move.wide_guard = true
		return ""
	var field_effect := ArenaConditions.field_effect_of_move(id, data)
	if not field_effect.is_empty():
		move.kind = Kind.ARENA
		move.field_effect = field_effect
		return ""
	var weather := ArenaConditions.weather_of_move(data)
	var surge := ArenaConditions.surge_of_move(data)
	var screen := str(data.get("sideCondition", ""))
	if screen in ArenaConditions.HAZARDS or id == "defog":
		move.kind = Kind.ARENA
		move.hazard = screen if screen in ArenaConditions.HAZARDS else ""
		return ""
	if id == "tidyup":
		move.kind = Kind.SELF_BUFF
		move.boosts = {"atk": 1, "spe": 1}
		return ""
	if not weather.is_empty() or not surge.is_empty() or screen in ArenaConditions.SCREENS:
		move.kind = Kind.ARENA
		move.weather = weather
		move.surge = surge
		move.screen = screen if screen in ArenaConditions.SCREENS else ""
		return ""
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


## True for kinds applied on release without reaching the foe (to the user, its ally or the
## arena).
func is_self() -> bool:
	return kind == Kind.SELF_BUFF or kind == Kind.HEAL or kind == Kind.ARENA or kind == Kind.ALLY or kind == Kind.REDIRECT


## True for doubles' ally moves, which standard movesets never pick (§9.6).
func is_ally_move() -> bool:
	return kind == Kind.ALLY or kind == Kind.REDIRECT or team_heal or wide_guard


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


## Melee and area moves can be feinted: theirs are the wind-ups a foe dodges.
func can_feint() -> bool:
	return kind == Kind.MELEE or kind == Kind.AREA


## The largest gap between hitboxes this move can be started from.
func reach() -> float:
	if kind == Kind.MELEE:
		return Rules.MELEE_DASH_RANGE
	if kind == Kind.AREA:
		return Rules.AREA_RADIUS
	if is_self():
		return INF
	return Rules.PROJECTILE_RANGE
