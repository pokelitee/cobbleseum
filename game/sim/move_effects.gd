class_name MoveEffects
extends RefCounted
## Damaging moves whose type, power or use follows the battle's state (concepts_brief.md §9.3,
## M18). Showdown works these out in code, so the data alone plays them as plain hits. A hit (and
## the AI's estimate of one) asks adapt() for the move as it is now: the same BattleMove when
## nothing applies, else a variant with its type and power changed (BattleMove.variant), which
## every later reading (STAB, effectiveness, abilities, items, the weather) then sees.
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
##
## Rules version 37, HP and state (power_now), read the main series' way except where noted:
## - the user's HP (Eruption, Water Spout, Dragon Energy, Reversal, Flail) or the target's (Hard
##   Press, Crush Grip, Wring Out, Brine);
## - a status condition (Facade, which ignores burn's halving, Hex, Infernal Parade, Venoshock,
##   Barb Barrage); stat stages (Stored Power, Power Trip); weight (Grass Knot, Low Kick, Heavy
##   Slam, Heat Crash) and Speed (Gyro Ball, Electro Ball); a held item (Acrobatics without one,
##   Knock Off against one); Gravity (Grav Apple);
## - what happened in the last Rules.RECENT_SECONDS, the real-time "this turn": the user hit by a
##   move (Payback, Avalanche, Revenge), the target hurt (Assurance), the user's last move missing
##   (Stomping Tantrum, Temper Flare), its stats lowered (Lash Out), a teammate fainting
##   (Retaliate);
## - the battle so far: teammates fainted (Last Respects), hits taken (Rage Fist), the same move
##   again soon after (Echoed Voice, Fury Cutter, Rollout, Ice Ball: Fighter.combo).
## The battle handles the rest: Collision Course, Electro Drift, Freeze-Dry, Flying Press and
## Synchronoise in the effectiveness (Battle.damage_parts), Fickle Beam's and Present's rolls,
## Triple Axel's and Triple Kick's rising hits, False Swipe, Knock Off taking the item, Focus
## Punch's channel; and usable() says which moves can be used against whom.

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

## Power that follows HP, from this much at full.
const USER_HP_POWER := {"eruption": 150, "waterspout": 150, "dragonenergy": 150}
const TARGET_HP_POWER := {"hardpress": 100, "crushgrip": 120, "wringout": 120}
## Reversal and Flail: [the user's HP in 48ths at most, power].
const LOW_HP_POWER := [[1, 200], [4, 150], [9, 100], [16, 80], [32, 40]]
const LOW_HP_POWER_FLOOR := 20
## Power ×2 when the target has any major status, or poison; Facade when the user has one of these.
const DOUBLED_ON_STATUS: Array[String] = ["hex", "infernalparade"]
const DOUBLED_ON_POISON: Array[String] = ["venoshock", "barbbarrage"]
const FACADE_STATUSES: Array[String] = ["brn", "par", "psn", "tox"]
## Stored Power and Power Trip: base power plus this for each stage the user has raised.
const STAGE_POWER := 20
## Grass Knot and Low Kick: [the target's weight in kg below, power], else the most.
const WEIGHT_POWER := [[10.0, 20], [25.0, 40], [50.0, 60], [100.0, 80], [200.0, 100]]
const WEIGHT_POWER_MAX := 120
## Heavy Slam and Heat Crash: [the user's weight over the target's at least, power], else the least.
const WEIGHT_RATIO_POWER := [[5.0, 120], [4.0, 100], [3.0, 80], [2.0, 60]]
const WEIGHT_RATIO_POWER_MIN := 40
## Gyro Ball: 25 × the target's Speed over the user's (+1), up to 150. Electro Ball: [the user's
## Speed over the target's at least, power], else the least.
const GYRO_FACTOR := 25.0
const GYRO_MAX := 150
const SPEED_RATIO_POWER := [[4.0, 150], [3.0, 120], [2.0, 80], [1.0, 60]]
const SPEED_RATIO_POWER_MIN := 40
## Moves doubled by what happened in the last Rules.RECENT_SECONDS.
const AFTER_BEING_HIT: Array[String] = ["payback", "avalanche", "revenge"]
const AFTER_MISSING: Array[String] = ["stompingtantrum", "temperflare"]
## Last Respects: +50 power per teammate fainted; Rage Fist: +50 per hit taken, up to 350.
const PER_FAINTED := 50
const PER_HIT := 50
const RAGE_FIST_MAX := 350
## Moves that grow with use soon after the last: power doubles each time, up to these powers.
const COMBO_MAX := {"furycutter": 160, "rollout": 480, "iceball": 480, "echoedvoice": 200}
## Knock Off is ×1.5 against a working item (Acrobatics doubles without one); Grav Apple ×1.5
## under Gravity.
const KNOCK_OFF_FACTOR := 1.5
const GRAV_APPLE_FACTOR := 1.5
## Collision Course and Electro Drift: ×4/3 on a super-effective hit.
const SUPER_EFFECTIVE_BOOSTED: Array[String] = ["collisioncourse", "electrodrift"]
const SUPER_EFFECTIVE_BOOST := 4.0 / 3.0
## Triple Axel and Triple Kick: each hit's power is the first's times its number.
const RISING_HITS: Array[String] = ["tripleaxel", "triplekick"]
## Fickle Beam doubles this often; Present heals this often instead of hitting, by the main
## series' quarter of max HP read as a per-hit share (a sixth of it, §9.9).
const FICKLE_CHANCE := 0.3
const PRESENT_HEAL_CHANCE := 0.2
const PRESENT_HEAL := 0.25 / 6.0
## Rules version 38: Counter and Mirror Coat pay back twice the physical or special damage taken
## from the target in the last Rules.RETURN_SECONDS, Metal Burst and Comeuppance 1.5 times any.
const RETURNS := {"counter": ["physical", 2.0], "mirrorcoat": ["special", 2.0], "metalburst": ["any", 1.5],
	"comeuppance": ["any", 1.5]}
## Moves that hit a random status: [chance in %, statuses].
const RANDOM_STATUS := {"triattack": [20, ["brn", "par", "frz"]], "direclaw": [50, ["psn", "par", "slp"]]}
## Moves that punish a foe whose stats rose in the last Rules.RECENT_SECONDS: Alluring Voice
## confuses it, Burning Jealousy burns it.
const AFTER_RAISING := {"alluringvoice": "confusion", "burningjealousy": "brn"}
## Moves that lay a hazard on the target's side when they hit.
const LAYS_HAZARD := {"ceaselessedge": "spikes", "stoneaxe": "stealthrock"}
## Valuing a move for a standard moveset: an HP-scaled move at the average HP share over a battle,
## and typical powers for moves whose data has none (or a misleading one).
const TYPICAL_HP_SHARE := 0.6
const TYPICAL_POWER := {"reversal": 60, "flail": 60, "grassknot": 60, "lowkick": 60, "heavyslam": 60, "heatcrash": 60,
	"gyroball": 60, "electroball": 60, "storedpower": 40, "powertrip": 40, "ragefist": 100, "present": 60}
## Moves that only work some of the time (usable()), or land late (Future Sight), count for about
## this share of their power in a standard moveset.
const MOVESET_SHARE := {"suckerpunch": 0.5, "thunderclap": 0.5, "upperhand": 0.1, "fakeout": 0.1, "firstimpression": 0.2,
	"dreameater": 0.1, "belch": 0.2, "lastresort": 0.3, "synchronoise": 0.3, "focuspunch": 0.6, "poltergeist": 0.9,
	"futuresight": 0.85, "doomdesire": 0.85, "spitup": 0.0, "endeavor": 0.4, "counter": 0.4, "mirrorcoat": 0.4, "metalburst": 0.4, "comeuppance": 0.4}


## `move` as `attacker` would use it on `defender` now.
static func adapt(attacker: Fighter, defender: Fighter, move: BattleMove) -> BattleMove:
	if move.adapted or not move.is_damaging() or move.fixed_damage > 0:
		return move
	var arena := attacker.arena
	var power := power_now(attacker, defender, move)
	# Charge doubles the next Electric move (rules version 39).
	if attacker.charged_ticks > 0 and move.type == "Electric":
		power *= StatusMoves.CHARGE_FACTOR
	return _with_conditions(move, arena.weather_for(attacker), arena.surge_for(attacker), arena.surge_for(defender), power)


## `move` under weather `weather` and surge `surge` (each "" for none) from a user that is or
## isn't `user_grounded` at a target that is or isn't `target_grounded` (a surge only reaches
## grounded fighters); for valuing a condition or a moveset before a battle.
static func in_conditions(move: BattleMove, weather: String, surge: String, user_grounded := true, target_grounded := true) -> BattleMove:
	if move.adapted or not move.is_damaging() or move.fixed_damage > 0:
		return move
	return _with_conditions(move, weather, surge if user_grounded else "", surge if target_grounded else "", float(move.power))


## `move`'s power from the state of `attacker` and `defender` (rules version 37), before the
## weather and surge.
static func power_now(attacker: Fighter, defender: Fighter, move: BattleMove) -> float:
	var power := float(move.power)
	var id := move.id
	if USER_HP_POWER.has(id):
		return maxf(1.0, USER_HP_POWER[id] * attacker.hp / float(attacker.max_hp))
	if TARGET_HP_POWER.has(id):
		return maxf(1.0, TARGET_HP_POWER[id] * defender.hp / float(defender.max_hp))
	match id:
		"reversal", "flail":
			var share := floori(48.0 * attacker.hp / attacker.max_hp)
			for step: Array in LOW_HP_POWER:
				if share <= int(step[0]):
					return step[1]
			return LOW_HP_POWER_FLOOR
		"brine":
			return power * 2.0 if defender.hp * 2 <= defender.max_hp else power
		"facade":
			return power * 2.0 if attacker.status in FACADE_STATUSES else power
		"storedpower", "powertrip":
			var raised := 0
			for stat: String in attacker.boosts:
				raised += maxi(0, int(attacker.boosts[stat]))
			return power + STAGE_POWER * raised
		"grassknot", "lowkick":
			for step: Array in WEIGHT_POWER:
				if defender.weight_kg < float(step[0]):
					return step[1]
			return WEIGHT_POWER_MAX
		"heavyslam", "heatcrash":
			var ratio := attacker.weight_kg / maxf(defender.weight_kg, 0.1)
			for step: Array in WEIGHT_RATIO_POWER:
				if ratio >= float(step[0]):
					return step[1]
			return WEIGHT_RATIO_POWER_MIN
		"gyroball":
			return minf(GYRO_MAX, floorf(GYRO_FACTOR * defender.stat("spe") / maxf(attacker.stat("spe"), 1.0)) + 1.0)
		"electroball":
			var ratio := attacker.stat("spe") / maxf(defender.stat("spe"), 1.0)
			for step: Array in SPEED_RATIO_POWER:
				if ratio >= float(step[0]):
					return step[1]
			return SPEED_RATIO_POWER_MIN
		"acrobatics":
			return power * 2.0 if not item_works(attacker) else power
		"knockoff":
			return power * KNOCK_OFF_FACTOR if item_works(defender) else power
		"gravapple":
			return power * GRAV_APPLE_FACTOR if attacker.arena.has_field("gravity") else power
		"assurance":
			return power * 2.0 if defender.hurt_ticks > 0 else power
		"lashout":
			return power * 2.0 if attacker.lowered_ticks > 0 else power
		"retaliate":
			return power * 2.0 if attacker.arena.fainted_ticks[attacker.side] > 0 else power
		"lastrespects":
			return power + PER_FAINTED * attacker.arena.fainted[attacker.side]
		"ragefist":
			return minf(RAGE_FIST_MAX, power + PER_HIT * attacker.times_hit)
		"spitup":
			return StatusMoves.SPIT_UP_POWER * attacker.stockpile
	if id in DOUBLED_ON_STATUS and not defender.status.is_empty():
		return power * 2.0
	if id in DOUBLED_ON_POISON and defender.status in ["psn", "tox"]:
		return power * 2.0
	if id in AFTER_BEING_HIT and attacker.hit_ticks > 0:
		return power * 2.0
	if id in AFTER_MISSING and attacker.missed_ticks > 0:
		return power * 2.0
	if COMBO_MAX.has(id) and attacker.combo.get("move", "") == id and int(attacker.combo.get("ticks", 0)) > 0:
		return minf(COMBO_MAX[id], power * pow(2.0, int(attacker.combo.count)))
	return power


## Whether `fighter`'s held item still works: one held, not under Magic Room, not a spent one-use item.
static func item_works(fighter: Fighter) -> bool:
	return not fighter.item_effect.is_empty() and not fighter.item_used


## `user_surge` and `target_surge` are the surge under each, "" for one that's airborne; `power`
## the move's power before them.
static func _with_conditions(move: BattleMove, weather: String, user_surge: String, target_surge: String, power: float) -> BattleMove:
	var type := move.type
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
	return move.variant(type, maxi(1, roundi(power)))


## Whether `fighter` can use `move` against `foe` now (rules version 37):
## - Sucker Punch and Thunderclap only while the foe winds up an attack, Upper Hand only while it
##   winds up a priority one (a feint looks the same, so it counts);
## - Fake Out and First Impression only in the user's first Rules.FIRST_SECONDS out;
## - Dream Eater only on a sleeping foe, Poltergeist only on one holding a working item;
## - Belch only after the user has eaten its berry, Last Resort only once its other moves have
##   all been used since it came out.
static func usable(fighter: Fighter, foe: Fighter, move: BattleMove) -> bool:
	if not Volatiles.allows(fighter, move) or Volatiles.imprisoned([foe, foe.ally] if foe.ally != null else [foe], move):
		return false
	match move.id:
		"suckerpunch", "thunderclap":
			return foe.action == Fighter.Action.WINDUP and foe.moves[foe.action_move].is_damaging()
		"upperhand":
			return foe.action == Fighter.Action.WINDUP and foe.moves[foe.action_move].is_damaging() \
				and foe.moves[foe.action_move].priority > 0
		"fakeout", "firstimpression":
			return fighter.out_ticks < Rules.seconds_to_ticks(Rules.FIRST_SECONDS)
		"dreameater":
			return foe.status == "slp"
		"poltergeist":
			return item_works(foe)
		"belch":
			var held := Items.effect(fighter.item)
			return fighter.item_used and (held.has("berry_heal") or held.get("cures_status", false))
		"lastresort":
			for other in fighter.moves:
				if other != move and not fighter.used_moves.has(other.id):
					return false
			return fighter.moves.size() > 1
		"endeavor":
			return foe.hp > fighter.hp
	if RETURNS.has(move.id):
		return returned(fighter, foe, move) > 0
	# One Future Sight at a time.
	if move.delayed:
		return fighter.foresight.is_empty()
	return StatusMoves.usable(fighter, foe, move)


## Damage a rule-damage move (BattleMove.damage_rule) deals now, before overtime; the main series'
## shares of HP read as per-hit shares (Rules.HP_SHARE_READING).
static func rule_damage(attacker: Fighter, defender: Fighter, move: BattleMove) -> int:
	match move.damage_rule:
		"half":
			return maxi(1, floori(defender.hp * 0.5 * Rules.HP_SHARE_READING))
		"gap":
			return maxi(0, floori((defender.hp - attacker.hp) * Rules.HP_SHARE_READING))
		"gambit":
			return maxi(1, floori(attacker.hp * Rules.HP_SHARE_READING))
	return returned(attacker, defender, move)


## What Counter and its kin would pay back now: the damage of their kind `fighter` took from
## `foe` in the last Rules.RETURN_SECONDS, times their factor.
static func returned(fighter: Fighter, foe: Fighter, move: BattleMove) -> int:
	var rule: Array = RETURNS.get(move.id, [])
	if rule.is_empty():
		return 0
	var total := 0
	for taken: Dictionary in fighter.taken:
		if int(taken.side) == foe.side and int(taken.slot) == foe.slot and (rule[0] == "any" or (rule[0] == "physical") == taken.physical):
			total += int(taken.amount)
	return floori(total * float(rule[1]))


## Power for valuing `move` in a standard moveset where its power follows the battle's state
## (rules version 37): about what it deals over a typical battle, never its best case.
static func typical_power(move: BattleMove) -> float:
	if USER_HP_POWER.has(move.id):
		return USER_HP_POWER[move.id] * TYPICAL_HP_SHARE
	if TARGET_HP_POWER.has(move.id):
		return TARGET_HP_POWER[move.id] * TYPICAL_HP_SHARE
	return float(TYPICAL_POWER.get(move.id, move.power))


## Main-series effectiveness of `move` on `defender` (whose types, after Gravity, are `types`):
## Freeze-Dry is super effective on Water, Flying Press adds Flying's effectiveness, and
## Synchronoise only reaches a foe sharing a type with the user (else it's an immunity).
static func effectiveness(attacker: Fighter, defender: Fighter, move: BattleMove, types: Array, data: BattleData) -> float:
	match move.id:
		"freezedry":
			if "Water" in types:
				return 2.0 * data.effectiveness(move.type, types.filter(func(type: String) -> bool: return type != "Water"))
		"flyingpress":
			return data.effectiveness(move.type, types) * data.effectiveness("Flying", types)
		"synchronoise":
			if not attacker.types.any(func(type: String) -> bool: return type in defender.types):
				return 0.0
	# Rules version 40: Magnet Rise keeps Ground moves off (unless Gravity), Smack Down lets them
	# reach a Flying type, Tar Shot doubles Fire's effectiveness.
	if move.type == "Ground":
		if defender.volatiles.has("magnetrise") and not defender.arena.has_field("gravity"):
			return 0.0
		if defender.volatiles.has("smackdown") and "Flying" in types:
			types = types.filter(func(type: String) -> bool: return type != "Flying")
	if move.type == "Fire" and defender.volatiles.has("tarshot"):
		return 2.0 * data.effectiveness(move.type, types)
	return data.effectiveness(move.type, types)


## Present's power for a `roll` past its healing chance (0-1): 40, 80 or 120 at the main
## series' odds.
static func present_power(roll: float) -> int:
	if roll < PRESENT_HEAL_CHANCE + 0.4:
		return 40
	return 80 if roll < PRESENT_HEAL_CHANCE + 0.7 else 120
