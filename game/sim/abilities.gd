class_name Abilities
extends RefCounted
## Abilities (concepts_brief.md §9.9). Showdown implements abilities in code, so the effects
## are our own committed table, game/data/abilities.json, keyed by Showdown ability ID; each
## entry's keys say which effects it has. The battle and the AIs ask this class rather than
## reading the table, so every rule about an ability lives in one place.
##
## Real-time readings: an immunity plays like a type immunity (×0.25, no secondary effects);
## per-turn effects run at a fifth of their amount per second; effects that last until
## switching out last ABILITY_SECONDS.

const TABLE_FILE := "res://game/data/abilities.json"
## Pinch abilities (Blaze) power their type up at or below this share of max HP.
const PINCH_SHARE := 1.0 / 3.0
const PINCH_FACTOR := 1.5
## How long Flash Fire's boost lasts, and how often Intimidate strikes again.
const ABILITY_SECONDS := 12.0
const INTIMIDATE_SECONDS := 12.0
## Contact punishers' chance of a status, per melee hit taken.
const CONTACT_STATUS_CHANCE := 0.3
## Poison Heal restores this share of max HP per second instead of poison's damage.
const POISON_HEAL := 1.0 / 40.0

static var _table := {}


## The table: ability ID -> its entry (`name`, `value` and effect keys).
static func table() -> Dictionary:
	if _table.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE_FILE))
		assert(parsed is Dictionary, "%s is missing or invalid" % TABLE_FILE)
		for id: String in parsed:
			if not id.begins_with("_"):
				_table[id] = parsed[id]
	return _table


static func is_known(id: String) -> bool:
	return table().has(id)


## The entry for an ability ID, or {} for none or one the rules don't implement.
static func effect(id: String) -> Dictionary:
	return table().get(id, {})


static func display_name(id: String) -> String:
	return str(effect(id).get("name", id))


## The species' standard ability: its highest-valued ability in the table, ties broken by ID,
## or "" if none is implemented. `species` is its Showdown pokedex entry.
static func standard(species: Dictionary) -> String:
	var best := ""
	var best_value := -INF
	var listed: Dictionary = species.get("abilities", {})
	for slot: String in listed:
		var id := BattleData.to_id(str(listed[slot]))
		# Abilities that only act on an ally (doubles) are never standard, so singles keep theirs.
		if not is_known(id) or effect(id).get("doubles_only", false):
			continue
		var value := float(effect(id).get("value", 0))
		if value > best_value or (value == best_value and id < best):
			best = id
			best_value = value
	return best


## Whether `defender`'s ability makes it immune to `move` (a type or a kind of move).
static func immune(defender: Fighter, move: BattleMove) -> bool:
	var entry := defender.ability_effect
	if move.type in entry.get("immune", []):
		return true
	for flag: String in entry.get("immune_flags", []):
		if move.flags.has(flag):
			return true
	return false


## Whether `defender` gains from being hit by `move` (an absorb): attacking into it helps it.
static func absorbs(defender: Fighter, move: BattleMove) -> bool:
	var entry := defender.ability_effect
	return move.type in entry.get("immune", []) and (entry.has("absorb_heal") or entry.has("absorb_boosts") or entry.has("absorb_power"))


## Main-series effectiveness after abilities: an ability immunity counts as an immunity, and
## Tinted Lens doubles resisted hits.
static func effectiveness(attacker: Fighter, defender: Fighter, move: BattleMove, main_series: float) -> float:
	if immune(defender, move):
		return 0.0
	if attacker.ability_effect.get("tinted_lens", false) and main_series > 0.0 and main_series < 1.0:
		return main_series * 2.0
	return main_series


## A stat's multiplier from its owner's ability: always (Huge Power), with a status (Guts), or
## in a weather or surge (Swift Swim, Solar Power, Surge Surfer, Grass Pelt).
static func stat_factor(fighter: Fighter, stat: String) -> float:
	var entry := fighter.ability_effect
	var factor := float(entry.get("stat_factors", {}).get(stat, 1.0))
	if not fighter.status.is_empty():
		factor *= float(entry.get("status_stat_factors", {}).get(stat, 1.0))
	if entry.has("weather_stats"):
		factor *= float(entry.weather_stats.get(fighter.arena.weather_for(fighter), {}).get(stat, 1.0))
	if entry.has("surge_stats"):
		factor *= float(entry.surge_stats.get(fighter.arena.surge, {}).get(stat, 1.0))
	return factor


## STAB for the attacker: 1.5, or Adaptability's 2.
static func stab(attacker: Fighter) -> float:
	return float(attacker.ability_effect.get("stab", Rules.STAB))


## The attacker's power multiplier for `move`: the ability's constant boosts (move_factor), a
## pinch ability's, Flash Fire's once absorbed, and a weather's (Sand Force).
static func power_factor(attacker: Fighter, move: BattleMove) -> float:
	var entry := attacker.ability_effect
	var factor := move_factor(entry, move)
	if entry.has("weather_power"):
		var weather_power: Dictionary = entry.weather_power.get(attacker.arena.weather_for(attacker), {})
		if not weather_power.is_empty() and move.type in weather_power.types:
			factor *= float(weather_power.factor)
	if entry.get("pinch_type", "") == move.type and attacker.hp <= attacker.max_hp * PINCH_SHARE:
		factor *= PINCH_FACTOR
	if attacker.flash_fire_ticks > 0 and move.type in entry.get("immune", []):
		factor *= float(entry.get("absorb_power", 1.0))
	return factor


## The power multiplier an ability (its table `entry`) always gives `move`, whatever the
## battle's state: Technician, flag boosts (Iron Fist), Reckless and Sheer Force. The moveset
## policy values moves with it too.
static func move_factor(entry: Dictionary, move: BattleMove) -> float:
	var factor := 1.0
	if entry.has("technician") and move.power <= int(entry.technician) and move.fixed_damage == 0:
		factor *= 1.5
	var flag_power: Dictionary = entry.get("flag_power", {})
	for flag: String in flag_power:
		if move.flags.has(flag):
			factor *= float(flag_power[flag])
	if entry.has("recoil_power") and move.recoil_share > 0.0:
		factor *= float(entry.recoil_power)
	if entry.has("sheer_force") and not move.secondaries.is_empty():
		factor *= float(entry.sheer_force)
	return factor


## The defender's damage multiplier for a hit of `move` at main-series `effectiveness`.
static func taken_factor(defender: Fighter, move: BattleMove, effectiveness: float) -> float:
	var entry := defender.ability_effect
	var factor := float(entry.get("taken_types", {}).get(move.type, 1.0))
	if effectiveness > 1.0:
		factor *= float(entry.get("super_effective_taken", 1.0))
	if defender.hp >= defender.max_hp:
		factor *= float(entry.get("full_hp_taken", 1.0))
	return factor


## Whether a move's secondary effects apply: never with Sheer Force (it trades them for power)
## or against Shield Dust.
static func secondaries_apply(attacker: Fighter, defender: Fighter) -> bool:
	return not attacker.ability_effect.has("sheer_force") and not defender.ability_effect.get("shield_dust", false)


static func secondary_chance_factor(attacker: Fighter) -> float:
	return float(attacker.ability_effect.get("secondary_chance", 1.0))


## Whether the fighter's ability prevents status `status` ("confusion" included), always or in
## its weather (Leaf Guard: major status in sun).
static func status_immune(fighter: Fighter, status: String) -> bool:
	var entry := fighter.ability_effect
	if status in entry.get("status_immune", []):
		return true
	return status != "confusion" and entry.has("weather_status_immune") 		and str(entry.weather_status_immune) == fighter.arena.weather_for(fighter)


## The weather the fighter's ability sets when the battle starts (Drizzle), or "".
static func sets_weather(fighter: Fighter) -> String:
	return str(fighter.ability_effect.get("sets_weather", ""))


## The surge the fighter's ability sets when the battle starts (Electric Surge), or "".
static func sets_surge(fighter: Fighter) -> String:
	return str(fighter.ability_effect.get("sets_surge", ""))


## The stat changes from `changes` the foe can make to `fighter`, after its ability.
static func allowed_drops(fighter: Fighter, changes: Dictionary) -> Dictionary:
	var blocked: Array = fighter.ability_effect.get("no_lowering", [])
	var allowed := {}
	for stat: String in changes:
		if int(changes[stat]) < 0 and stat in blocked:
			continue
		allowed[stat] = changes[stat]
	return allowed


## Whether recoil and other damage outside hits are ignored.
static func no_recoil(fighter: Fighter) -> bool:
	return fighter.ability_effect.get("no_recoil", false) or fighter.ability_effect.get("magic_guard", false)


static func magic_guard(fighter: Fighter) -> bool:
	return fighter.ability_effect.get("magic_guard", false)


## Whether the fighter's ability hurts or afflicts a foe that strikes it in melee.
static func punishes_contact(fighter: Fighter) -> bool:
	return fighter.ability_effect.has("contact_status") or fighter.ability_effect.has("contact_damage")
