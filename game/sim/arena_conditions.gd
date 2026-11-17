class_name ArenaConditions
extends RefCounted
## Arena conditions (concepts_brief.md §9.11): the weather over the whole battle, the surge
## on its ground, and each side's screens. The battle owns one and both fighters share it, so stats and damage read it
## wherever they're worked out; a Fighter made on its own gets an empty one. Every rule about
## what a condition does lives here or in the ability and item tables.

const WEATHERS: Array[String] = ["rain", "sun", "sand", "snow"]
## Showdown's `weather` values on moves (lower-cased) -> weathers.
const SHOWDOWN_WEATHERS := {"raindance": "rain", "sunnyday": "sun", "sandstorm": "sand", "snowscape": "snow"}
const NAMES := {"rain": "Rain", "sun": "Harsh sunlight", "sand": "Sandstorm", "snow": "Snow"}
## Rain and sun power up one move type and weaken another (a Utility Umbrella's holder is
## out of both).
const BOOSTED := {"rain": "Water", "sun": "Fire"}
const WEAKENED := {"rain": "Fire", "sun": "Water"}
const BOOST := 1.5
const WEAKEN := 0.5
## A sandstorm hurts every fighter but these types once a second: half Leftovers' rate, since
## it comes on top of a held item.
const SAND_DAMAGE := 1.0 / 160.0
const SAND_PROOF_TYPES: Array[String] = ["Rock", "Ground", "Steel"]
## Sand and snow raise one type's defence.
const DEFENSE_BOOSTS := {"sand": {"type": "Rock", "stat": "spd"}, "snow": {"type": "Ice", "stat": "def"}}
const DEFENSE_BOOST := 1.5
## Moves that skip their charge in sun, and moves that fly at full accuracy's speed in a weather.
const SUN_SKIPS_CHARGE: Array[String] = ["solarbeam", "solarblade"]
const SURE_IN := {"thunder": "rain", "hurricane": "rain", "blizzard": "snow"}
## Heals whose amount follows the weather, as main-series shares of max HP: more in their
## favoured weather, less in any other (Shore Up only gains).
const WEATHER_HEALS := {"morningsun": "sun", "synthesis": "sun", "moonlight": "sun", "shoreup": "sand"}
const FAVOURED_HEAL := 2.0 / 3.0
const UNFAVOURED_HEAL := 0.25
const ONLY_GAINS: Array[String] = ["shoreup"]
## Surges, from Showdown's `terrain` values on moves. They act on grounded fighters only (not
## Flying types or Levitate): one move type powered up for a grounded attacker, Grassy
## healing, and protection from some statuses and moves for a grounded defender.
const SURGES: Array[String] = ["electric", "grassy", "misty", "psychic"]
const SHOWDOWN_SURGES := {"electricterrain": "electric", "grassyterrain": "grassy", "mistyterrain": "misty",
	"psychicterrain": "psychic"}
const SURGE_NAMES := {"electric": "Electric surge", "grassy": "Grassy surge", "misty": "Misty surge", "psychic": "Psychic surge"}
const SURGE_TYPES := {"electric": "Electric", "grassy": "Grass", "psychic": "Psychic"}
const SURGE_BOOST := 1.3
## Grassy healing runs at half Leftovers' rate, like weather healing.
const GRASSY_HEAL := 1.0 / 160.0
## Grassy ground softens these moves, and misty ground Dragon moves, against grounded fighters.
const GRASSY_SOFTENS: Array[String] = ["earthquake", "bulldoze", "magnitude"]
const SOFTENED := 0.5
## Valuing a surge's protection: Electric's from sleep, Misty's from every status, as a share of
## HP a second.
const SURGE_SHIELD := {"electric": 0.0005, "misty": 0.002}
## Screens soften hits on their side: Reflect physical ones, Light Screen special ones, Aurora
## Veil (only in snow) both. Critical hits and Infiltrator get through; these moves shatter the
## foe's screens before they hit.
const SCREENS: Array[String] = ["reflect", "lightscreen", "auroraveil"]
const SCREEN_NAMES := {"reflect": "Reflect", "lightscreen": "Light Screen", "auroraveil": "Aurora Veil"}
const SCREEN_FACTOR := 0.5
const SCREEN_BREAKERS: Array[String] = ["brickbreak", "psychicfangs", "ragingbull"]
## Valuing a weather (weather_gain): a fighter deals about its foe's whole HP in a battle of
## this many seconds, so a damage factor is worth that rate over the weather's time; doubling
## walking speed is worth this share of HP a second.
const DAMAGE_SECONDS := 40.0
const SPEED_GAIN := 0.005

var weather := ""
## Ticks the weather has left; -1 for one that lasts the battle (an arena's starting weather).
var weather_ticks := 0
var surge := ""
var surge_ticks := 0
## Each side's screens: {name: ticks left}.
var screens: Array[Dictionary] = [{}, {}]


## The weather a Showdown move sets ("" for none).
static func weather_of_move(data: Dictionary) -> String:
	return SHOWDOWN_WEATHERS.get(str(data.get("weather", "")).to_lower(), "")


static func display_name(name: String) -> String:
	return str(NAMES.get(name, SURGE_NAMES.get(name, name)))


## The surge a Showdown move sets ("" for none).
static func surge_of_move(data: Dictionary) -> String:
	return SHOWDOWN_SURGES.get(str(data.get("terrain", "")).to_lower(), "")


## Sets the weather for `ticks` (-1: the rest of the battle).
func set_weather(name: String, ticks: int) -> void:
	weather = name
	weather_ticks = ticks


func set_surge(name: String, ticks: int) -> void:
	surge = name
	surge_ticks = ticks


## Counts the conditions down a tick. Returns those that just ended, as {"weather": name} or
## {"surge": name}.
func tick() -> Array[Dictionary]:
	var ended: Array[Dictionary] = []
	if not weather.is_empty() and weather_ticks > 0:
		weather_ticks -= 1
		if weather_ticks == 0:
			ended.append({"weather": weather})
			weather = ""
	if not surge.is_empty() and surge_ticks > 0:
		surge_ticks -= 1
		if surge_ticks == 0:
			ended.append({"surge": surge})
			surge = ""
	for side in 2:
		for name: String in screens[side].keys():
			screens[side][name] -= 1
			if screens[side][name] <= 0:
				screens[side].erase(name)
				ended.append({"screen": name, "side": side})
	return ended


## Raises screen `name` on `side` for `ticks`.
func set_screen(side: int, name: String, ticks: int) -> void:
	screens[side][name] = ticks


## Ticks a screen raised by `setter` lasts: longer with Light Clay.
static func screen_ticks_for(setter: Fighter) -> int:
	var extended: bool = setter.item_effect.get("screen_extends", false)
	return Rules.seconds_to_ticks(Rules.SCREEN_EXTENDED_SECONDS if extended else Rules.SCREEN_SECONDS)


## The screens' multiplier on a hit of `move` on `defender` that isn't a critical hit.
func screen_factor(attacker: Fighter, defender: Fighter, move: BattleMove) -> float:
	var up: Dictionary = screens[defender.side]
	if up.is_empty() or attacker.ability_effect.get("infiltrator", false) or move.fixed_damage > 0:
		return 1.0
	return SCREEN_FACTOR if covers(up, move) else 1.0


## Whether the screens `up` ({name: ticks}) soften `move`.
static func covers(up: Dictionary, move: BattleMove) -> bool:
	return up.has("auroraveil") or up.has("reflect" if move.physical else "lightscreen")


## Whether `fighter` can use `move` under the conditions: Aurora Veil only in snow.
func usable(fighter: Fighter, move: BattleMove) -> bool:
	return move.screen != "auroraveil" or weather == "snow"


## What raising screen `name` now is worth to `me` against `foe`, as a share of HP: half the
## foe's damage of the kinds it softens, over its time.
func screen_value(me: Fighter, foe: Fighter, name: String) -> float:
	if screens[me.side].has(name) or foe.ability_effect.get("infiltrator", false):
		return 0.0
	var seconds := screen_ticks_for(me) / float(Rules.TICK_RATE)
	return screen_gain(foe.moves, name, seconds)


## What screen `name` is worth over `seconds` against a foe with `attacks`: the share of its
## damage (by power) the screen softens, halved.
static func screen_gain(attacks: Array, name: String, seconds: float) -> float:
	var total := 0.0
	var softened := 0.0
	var up := {name: 1}
	for move: BattleMove in attacks:
		if not move.is_damaging():
			continue
		var weight := move.power * move.expected_hits()
		total += weight
		if covers(up, move) and move.fixed_damage == 0:
			softened += weight
	if total <= 0.0:
		return 0.0
	return (1.0 - SCREEN_FACTOR) * softened / total * seconds / DAMAGE_SECONDS


## Ticks a weather set by `setter`'s move or ability lasts: longer with its extending item.
static func weather_ticks_for(setter: Fighter, name: String) -> int:
	var extended := str(setter.item_effect.get("weather_extends", "")) == name
	return Rules.seconds_to_ticks(Rules.WEATHER_EXTENDED_SECONDS if extended else Rules.WEATHER_SECONDS)


## Ticks a surge set by `setter` lasts: longer with a Terrain Extender.
static func surge_ticks_for(setter: Fighter) -> int:
	var extended: bool = setter.item_effect.get("surge_extends", false)
	return Rules.seconds_to_ticks(Rules.WEATHER_EXTENDED_SECONDS if extended else Rules.WEATHER_SECONDS)


## Whether a surge reaches `fighter`: not a Flying type or a Levitate user.
static func grounded(fighter: Fighter) -> bool:
	return _grounded(fighter.types, fighter.ability)


static func _grounded(types: Array, ability_id: String) -> bool:
	return not "Flying" in types and ability_id != "levitate"


## The surge acting on `fighter`, or "" if there's none or it isn't grounded.
func surge_for(fighter: Fighter) -> String:
	return surge if grounded(fighter) else ""


## The weather that acts on `fighter`: a Utility Umbrella keeps rain and sun off its holder.
func weather_for(fighter: Fighter) -> String:
	return _effective(weather, fighter.item_effect)


static func _effective(name: String, item: Dictionary) -> String:
	if item.get("umbrella", false) and BOOSTED.has(name):
		return ""
	return name


## The conditions' damage multiplier on a hit of `move`: rain and sun on Water and Fire, a
## surge powering its type for a grounded attacker, and grassy or misty ground softening hits on
## a grounded defender.
func damage_factor(attacker: Fighter, defender: Fighter, move: BattleMove) -> float:
	var factor := 1.0
	var name := weather_for(attacker)
	if not name.is_empty() and not weather_for(defender).is_empty():
		factor *= type_factor(name, move.type)
	if not surge.is_empty():
		factor *= surge_factor(surge, move, grounded(attacker), grounded(defender))
	return factor


## Surge `name`'s multiplier on `move` from an attacker and onto a defender that are or aren't
## grounded.
static func surge_factor(name: String, move: BattleMove, attacker_grounded: bool, defender_grounded: bool) -> float:
	var factor := 1.0
	if attacker_grounded and SURGE_TYPES.get(name, "") == move.type:
		factor *= SURGE_BOOST
	if defender_grounded and ((name == "grassy" and move.id in GRASSY_SOFTENS) or (name == "misty" and move.type == "Dragon")):
		factor *= SOFTENED
	return factor


static func type_factor(name: String, move_type: String) -> float:
	if BOOSTED.get(name, "") == move_type:
		return BOOST
	if WEAKENED.get(name, "") == move_type:
		return WEAKEN
	return 1.0


## A stat's multiplier from the weather: Rock types' Sp. Def in sand, Ice types' Defense in snow.
func stat_factor(fighter: Fighter, stat: String) -> float:
	var boost: Dictionary = DEFENSE_BOOSTS.get(weather, {})
	if not boost.is_empty() and boost.stat == stat and boost.type in fighter.types:
		return DEFENSE_BOOST
	return 1.0


## Ticks `fighter` winds `move` up for, from its usual wind-up: Solar Beam skips its charge in sun.
func windup_ticks(fighter: Fighter, move: BattleMove, ticks: int) -> int:
	if move.charges and move.id in SUN_SKIPS_CHARGE and weather_for(fighter) == "sun":
		return maxi(1, ticks - Rules.seconds_to_ticks(Rules.CHARGE_EXTRA))
	return ticks


## A projectile's speed in m/s: Thunder and Hurricane in rain, Blizzard in snow fly as if sure to hit.
func projectile_speed(fighter: Fighter, move: BattleMove) -> float:
	if SURE_IN.has(move.id) and weather_for(fighter) == SURE_IN[move.id]:
		return Rules.projectile_speed(100)
	return move.projectile_speed


## The share of max HP a heal restores, after the weather (Morning Sun, Synthesis, Moonlight,
## Shore Up).
func heal_share(fighter: Fighter, move: BattleMove) -> float:
	if not WEATHER_HEALS.has(move.id):
		return move.heal_share
	var name := weather_for(fighter)
	if name == WEATHER_HEALS[move.id]:
		return FAVOURED_HEAL * Rules.HEAL_FACTOR
	if not name.is_empty() and not move.id in ONLY_GAINS:
		return UNFAVOURED_HEAL * Rules.HEAL_FACTOR
	return move.heal_share


## Whether the conditions stop `fighter` getting `status` ("confusion" included): nobody freezes
## in sun, grounded fighters don't fall asleep on electric ground or get any status on misty
## ground.
func blocks_status(fighter: Fighter, status: String) -> bool:
	if status == "frz" and weather_for(fighter) == "sun":
		return true
	var ground := surge_for(fighter)
	return ground == "misty" or (ground == "electric" and status == "slp")


## Ticks `fighter` winds `move` up for against `foe`, from its usual wind-up: a priority move
## aimed at a grounded foe on psychic ground loses its quick wind-up.
func windup_against(foe: Fighter, move: BattleMove, ticks: int) -> int:
	if surge == "psychic" and move.priority > 0 and not move.is_self() and grounded(foe):
		return maxi(ticks, roundi(ticks / Rules.PRIORITY_WINDUP_FACTOR))
	return ticks


## The share of max HP a fighter of `types` with ability `ability` (an Abilities entry) gains
## (or, negative, loses) each second in weather `name`: sandstorm damage and the ability's own
## (Rain Dish, Dry Skin, Solar Power).
static func hp_per_second(types: Array, ability: Dictionary, name: String) -> float:
	var change := float(ability.get("weather_hp", {}).get(name, 0.0))
	if name == "sand" and not ability.get("weather_immune", false) and not SAND_PROOF_TYPES.any(func(t: String) -> bool: return t in types):
		change -= SAND_DAMAGE
	if change < 0.0 and ability.get("magic_guard", false):
		return 0.0
	return change


## The power multiplier a weather gives an attacker's `move` from its own side: the weather on
## the move's type, Sand Force, and Solar Power's Sp. Atk.
static func attack_factor(ability: Dictionary, move: BattleMove, name: String) -> float:
	var factor := type_factor(name, move.type)
	var power: Dictionary = ability.get("weather_power", {}).get(name, {})
	if not power.is_empty() and move.type in power.types:
		factor *= float(power.factor)
	factor *= float(ability.get("weather_stats", {}).get(name, {}).get(move.offensive_stat, 1.0))
	return factor


## What weather `name` is worth to a fighter (or a species choosing its moveset) over `seconds`,
## as a share of HP swung its way: its attacks' damage, its defence, HP lost or gained each
## second, and a speed-doubling ability. `attacks` are its damaging BattleMoves.
static func weather_gain(types: Array, ability: Dictionary, item: Dictionary, attacks: Array, name: String, seconds: float) -> float:
	name = _effective(name, item)
	if name.is_empty():
		return 0.0
	var gain := hp_per_second(types, ability, name) * seconds
	var total := 0.0
	var boosted := 0.0
	for move: BattleMove in attacks:
		if not move.is_damaging():
			continue
		var weight := (move.power if move.fixed_damage == 0 else Rules.FIXED_DAMAGE_POWER) * move.expected_hits()
		total += weight
		boosted += weight * (attack_factor(ability, move, name) if move.fixed_damage == 0 else 1.0)
	if total > 0.0:
		gain += (boosted / total - 1.0) * seconds / DAMAGE_SECONDS
	var boost: Dictionary = DEFENSE_BOOSTS.get(name, {})
	if not boost.is_empty() and boost.type in types:
		# One of the two defences: about half the foe's hits are weakened.
		gain += (1.0 - 1.0 / DEFENSE_BOOST) * 0.5 * seconds / DAMAGE_SECONDS
	if ability.get("weather_stats", {}).get(name, {}).has("spe"):
		gain += SPEED_GAIN * seconds
	return gain


static func fighter_gain(fighter: Fighter, name: String, seconds: float) -> float:
	return weather_gain(fighter.types, fighter.ability_effect, fighter.item_effect, fighter.moves, name, seconds)


## What surge `name` is worth to a fighter (or a species choosing its moveset) of `types` with
## ability `ability_id` and `attacks`, over `seconds`, as a share of HP swung its way: its
## attacks on a foe that is or isn't `foe_grounded`, Grassy healing, protection from statuses,
## and its ability's surge stats. Hits it takes are the foe's gain.
static func surge_gain(types: Array, ability_id: String, attacks: Array, name: String, seconds: float, foe_grounded: bool) -> float:
	var ability := Abilities.effect(ability_id)
	var on_ground := _grounded(types, ability_id)
	var gain := 0.0
	var total := 0.0
	var boosted := 0.0
	for move: BattleMove in attacks:
		if not move.is_damaging():
			continue
		var weight := (move.power if move.fixed_damage == 0 else Rules.FIXED_DAMAGE_POWER) * move.expected_hits()
		total += weight
		boosted += weight * (surge_factor(name, move, on_ground, foe_grounded) if move.fixed_damage == 0 else 1.0)
	if total > 0.0:
		gain += (boosted / total - 1.0) * seconds / DAMAGE_SECONDS
	if on_ground:
		if name == "grassy":
			gain += GRASSY_HEAL * seconds
		gain += float(SURGE_SHIELD.get(name, 0.0)) * seconds
	var stats: Dictionary = ability.get("surge_stats", {}).get(name, {})
	if stats.has("spe"):
		gain += SPEED_GAIN * seconds
	if stats.has("def"):
		gain += (1.0 - 1.0 / float(stats.def)) * 0.5 * seconds / DAMAGE_SECONDS
	return gain


## What setting surge `name` now would swing toward `me` against `foe`, as a share of HP: the
## new surge for its full time, less what the current one would still have given.
func surge_value(me: Fighter, foe: Fighter, name: String) -> float:
	var seconds := surge_ticks_for(me) / float(Rules.TICK_RATE)
	var value := _surge_net(me, foe, name, seconds)
	if not surge.is_empty():
		value -= _surge_net(me, foe, surge, surge_ticks / float(Rules.TICK_RATE))
	return value


static func _surge_net(me: Fighter, foe: Fighter, name: String, seconds: float) -> float:
	return surge_gain(me.types, me.ability, me.moves, name, seconds, grounded(foe)) \
		- surge_gain(foe.types, foe.ability, foe.moves, name, seconds, grounded(me))


## Seconds the surge has left (0 for none).
func surge_seconds_left() -> float:
	return surge_ticks / float(Rules.TICK_RATE) if not surge.is_empty() else 0.0


## What setting weather `name` now would swing toward `me` against `foe`, as a share of HP: the
## new weather for its full time, less what the current one would still have given.
func weather_value(me: Fighter, foe: Fighter, name: String) -> float:
	var seconds := weather_ticks_for(me, name) / float(Rules.TICK_RATE)
	var value := fighter_gain(me, name, seconds) - fighter_gain(foe, name, seconds)
	if not weather.is_empty():
		var left := seconds if weather_ticks < 0 else weather_ticks / float(Rules.TICK_RATE)
		value -= fighter_gain(me, weather, left) - fighter_gain(foe, weather, left)
	return value


## Seconds the weather has left (INF for one that lasts the battle, 0 for none).
func weather_seconds_left() -> float:
	if weather.is_empty():
		return 0.0
	return INF if weather_ticks < 0 else weather_ticks / float(Rules.TICK_RATE)
