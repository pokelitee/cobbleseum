class_name Items
extends RefCounted
## Held items (concepts_brief.md §9.10). Like abilities, their effects are our own committed
## table, game/data/items.json, keyed by Showdown item ID; each entry's keys say which effects
## it has, and the battle and the AIs ask this class rather than reading the table. Readings
## follow §9.9: per-turn effects run at a fifth of their amount per second, per-hit shares of
## max HP are scaled down.

const TABLE_FILE := "res://game/data/items.json"
## The standard-item policy's thresholds, on base stats.
const VEST_BULK := 280
const ORB_ATTACK := 110
const ORB_BULK := 260
const HELMET_DEFENSE := 110
const HELMET_LEAD := 20
const SITRUS_HP := 100
## Moveset types at which an Expert Belt pays off: hitting many types super-effectively.
const BELT_TYPES := 3
## What a surge setter holds.
const SURGE_EXTENDER := "terrainextender"
const SCREEN_EXTENDER := "lightclay"

static var _table := {}


## The table: item ID -> its entry (`name` and effect keys).
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


static func effect(id: String) -> Dictionary:
	return table().get(id, {})


static func display_name(id: String) -> String:
	return str(effect(id).get("name", id))


## Whether the species can still evolve (Eviolite works for it): an evolution in the data.
static func can_evolve(species: Dictionary, data: BattleData) -> bool:
	for evo: Variant in species.get("evos", []):
		if data.species.has(BattleData.to_id(str(evo))):
			return true
	return false


## The species' standard item, by one policy on its base stats, types and standard moveset
## (`moves`, BattleMoves), in order: Eviolite if it can evolve; Assault Vest if it's bulky and
## carries no status-category move; Life Orb for a frail attacker; Rocky Helmet for a
## physically sturdy one; Expert Belt for wide coverage; Sitrus Berry for a lot of HP; then
## Black Sludge for Poison types and Leftovers for the rest. A species whose standard `ability`
## or moveset sets a weather holds that weather's rock, after Eviolite, one that sets a surge a
## Terrain Extender, and one that raises a screen Light Clay.
static func standard(species: Dictionary, moves: Array, data: BattleData, ability := "") -> String:
	var base: Dictionary = species.get("baseStats", {})
	var bulk := int(base.get("hp", 0)) + int(base.get("def", 0)) + int(base.get("spd", 0))
	var attack := maxi(int(base.get("atk", 0)), int(base.get("spa", 0)))
	var status_moves := moves.any(func(m: BattleMove) -> bool: return not m.is_damaging())
	var attack_types := {}
	for move: BattleMove in moves:
		if move.is_damaging():
			attack_types[move.type] = true
	if can_evolve(species, data):
		return "eviolite"
	var weather := str(Abilities.effect(ability).get("sets_weather", ""))
	for move: BattleMove in moves:
		if weather.is_empty() and move.kind == BattleMove.Kind.ARENA:
			weather = move.weather
	if not weather.is_empty():
		return weather_rock(weather)
	if not str(Abilities.effect(ability).get("sets_surge", "")).is_empty() \
			or moves.any(func(m: BattleMove) -> bool: return not m.surge.is_empty()):
		return SURGE_EXTENDER
	if moves.any(func(m: BattleMove) -> bool: return not m.screen.is_empty()):
		return SCREEN_EXTENDER
	if not status_moves and bulk >= VEST_BULK:
		return "assaultvest"
	if attack >= ORB_ATTACK and bulk < ORB_BULK:
		return "lifeorb"
	if int(base.get("def", 0)) >= HELMET_DEFENSE and int(base.get("def", 0)) >= int(base.get("spd", 0)) + HELMET_LEAD:
		return "rockyhelmet"
	if attack_types.size() >= BELT_TYPES:
		return "expertbelt"
	if int(base.get("hp", 0)) >= SITRUS_HP:
		return "sitrusberry"
	return "blacksludge" if "Poison" in species.get("types", []) else "leftovers"


## A stat's multiplier from the fighter's item (Assault Vest, Eviolite while it can evolve).
static func stat_factor(fighter: Fighter, stat: String) -> float:
	var entry := fighter.item_effect
	if entry.get("needs_evolution", false) and not fighter.can_evolve:
		return 1.0
	return float(entry.get("stat_factors", {}).get(stat, 1.0))


## The attacker's damage multiplier from its item for `move` at main-series `effectiveness`.
static func power_factor(attacker: Fighter, move: BattleMove, effectiveness: float) -> float:
	var entry := attacker.item_effect
	var factor := float(entry.get("power", 1.0))
	factor *= float(entry.get("type_power", {}).get(move.type, 1.0))
	factor *= float(entry.get("physical_power" if move.physical else "special_power", 1.0))
	if effectiveness > 1.0:
		factor *= float(entry.get("super_effective_power", 1.0))
	return factor


## Whether the item stops the fighter using `move` (Assault Vest and status moves).
static func forbids(fighter: Fighter, move: BattleMove) -> bool:
	return fighter.item_effect.get("no_status_moves", false) and not move.is_damaging()


static func punishes_contact(fighter: Fighter) -> bool:
	return fighter.item_effect.has("contact_damage")


## The item that lengthens weather `weather` (Damp Rock for rain).
static func weather_rock(weather: String) -> String:
	for id: String in table():
		if str(table()[id].get("weather_extends", "")) == weather:
			return id
	return ""
