class_name ArenaConditions
extends RefCounted
## Arena conditions (concepts_brief.md §9.11): the weather over the whole battle. The battle
## owns one and both fighters share it, so stats and damage read it wherever they're worked
## out; a Fighter made on its own gets an empty one. Every rule about what a weather does
## lives here or in the ability and item tables.

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
## Valuing a weather (weather_gain): a fighter deals about its foe's whole HP in a battle of
## this many seconds, so a damage factor is worth that rate over the weather's time; doubling
## walking speed is worth this share of HP a second.
const DAMAGE_SECONDS := 40.0
const SPEED_GAIN := 0.005

var weather := ""
## Ticks the weather has left; -1 for one that lasts the battle (an arena's starting weather).
var weather_ticks := 0


## The weather a Showdown move sets ("" for none).
static func weather_of_move(data: Dictionary) -> String:
	return SHOWDOWN_WEATHERS.get(str(data.get("weather", "")).to_lower(), "")


static func display_name(name: String) -> String:
	return str(NAMES.get(name, name))


## Sets the weather for `ticks` (-1: the rest of the battle).
func set_weather(name: String, ticks: int) -> void:
	weather = name
	weather_ticks = ticks


## Counts the weather down a tick. Returns the weather that just ended, or "".
func tick() -> String:
	if weather.is_empty() or weather_ticks < 0:
		return ""
	weather_ticks -= 1
	if weather_ticks > 0:
		return ""
	var ended := weather
	weather = ""
	weather_ticks = 0
	return ended


## Ticks a weather set by `setter`'s move or ability lasts: longer with its extending item.
static func weather_ticks_for(setter: Fighter, name: String) -> int:
	var extended := str(setter.item_effect.get("weather_extends", "")) == name
	return Rules.seconds_to_ticks(Rules.WEATHER_EXTENDED_SECONDS if extended else Rules.WEATHER_SECONDS)


## The weather that acts on `fighter`: a Utility Umbrella keeps rain and sun off its holder.
func weather_for(fighter: Fighter) -> String:
	return _effective(weather, fighter.item_effect)


static func _effective(name: String, item: Dictionary) -> String:
	if item.get("umbrella", false) and BOOSTED.has(name):
		return ""
	return name


## The weather's damage multiplier on a hit of `move` (rain and sun on Water and Fire).
func damage_factor(attacker: Fighter, defender: Fighter, move: BattleMove) -> float:
	var name := weather_for(attacker)
	if name.is_empty() or weather_for(defender).is_empty():
		return 1.0
	return type_factor(name, move.type)


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


## Whether the weather stops `fighter` getting `status` (nobody freezes in sun).
func blocks_status(fighter: Fighter, status: String) -> bool:
	return status == "frz" and weather_for(fighter) == "sun"


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
