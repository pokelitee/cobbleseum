class_name MoveEffects
extends RefCounted
## Damaging moves whose type or power follows the battle's state (concepts_brief.md §9.3, M18).
## Showdown works these out in code, so the data alone plays them as plain hits. A hit (and the
## AI's estimate of one) asks adapt() for the move as it is now: the same BattleMove when nothing
## applies, else a variant with its type and power changed (BattleMove.variant), which every
## later reading (STAB, effectiveness, abilities, items, the weather) then sees.
##
## Rules version 36, the weather and surge:
## - Weather Ball takes the weather's type at double power, Terrain Pulse the surge's (for a
##   grounded user);
## - Rising Voltage doubles against a grounded foe on electric ground; Expanding Force, Psyblade
##   and Misty Explosion are ×1.5 from a grounded user on their surge;
## - Solar Beam and Solar Blade are halved in rain, sand and snow.
## Timings and surges (ArenaConditions): Grassy Glide winds up like a priority move from a grounded
## user on grassy ground; Electro Shot skips its charge in rain as Solar Beam does in sun; Steel
## Roller needs a surge and Steel Roller and Ice Spinner end it when they hit; Hydro Steam is
## powered up in sun rather than weakened.

const WEATHER_TYPES := {"rain": "Water", "sun": "Fire", "sand": "Rock", "snow": "Ice"}
const SURGE_TYPES := {"electric": "Electric", "grassy": "Grass", "misty": "Fairy", "psychic": "Psychic"}
## Weather Ball and Terrain Pulse double in their condition.
const CONDITION_POWER := 2
## Moves powered up on one surge: [surge, whose ground it must be ("user" or "target"), factor].
const SURGE_POWER := {"risingvoltage": ["electric", "target", 2.0], "expandingforce": ["psychic", "user", 1.5],
	"psyblade": ["electric", "user", 1.5], "mistyexplosion": ["misty", "user", 1.5]}
## Solar Beam and Solar Blade lose half their power in any weather but sun.
const SOLAR: Array[String] = ["solarbeam", "solarblade"]
const SOLAR_DIMMED := 0.5


## `move` as `attacker` would use it on `defender` now.
static func adapt(attacker: Fighter, defender: Fighter, move: BattleMove) -> BattleMove:
	if move.adapted or not move.is_damaging() or move.fixed_damage > 0:
		return move
	var arena := attacker.arena
	return _with_conditions(move, arena.weather_for(attacker), arena.surge_for(attacker), arena.surge_for(defender))


## `move` under weather `weather` and surge `surge` (each "" for none) from a user that is or
## isn't `user_grounded` at a target that is or isn't `target_grounded` (a surge only reaches
## grounded fighters); for valuing a condition or a moveset before a battle.
static func in_conditions(move: BattleMove, weather: String, surge: String, user_grounded := true, target_grounded := true) -> BattleMove:
	if move.adapted or not move.is_damaging() or move.fixed_damage > 0:
		return move
	return _with_conditions(move, weather, surge if user_grounded else "", surge if target_grounded else "")


## `user_surge` and `target_surge` are the surge under each, "" for one that's airborne.
static func _with_conditions(move: BattleMove, weather: String, user_surge: String, target_surge: String) -> BattleMove:
	var type := move.type
	var power := float(move.power)
	match move.id:
		"weatherball":
			if WEATHER_TYPES.has(weather):
				type = WEATHER_TYPES[weather]
				power *= CONDITION_POWER
		"terrainpulse":
			if SURGE_TYPES.has(user_surge):
				type = SURGE_TYPES[user_surge]
				power *= CONDITION_POWER
	if SURGE_POWER.has(move.id):
		var boost: Array = SURGE_POWER[move.id]
		if (user_surge if boost[1] == "user" else target_surge) == boost[0]:
			power *= float(boost[2])
	if move.id in SOLAR and not weather.is_empty() and weather != "sun":
		power *= SOLAR_DIMMED
	if type == move.type and roundi(power) == move.power:
		return move
	return move.variant(type, roundi(power))
