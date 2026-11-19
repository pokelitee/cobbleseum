class_name PlateEffects
extends RefCounted
## What a fighter's name plate shows in its row under the HP bar (concepts_brief.md §12.5): its
## status condition, confusion and its side's screens and side conditions (Tailwind, Safeguard,
## Mist), each with the share of its time left,
## then its changed stat stages, read from the battle every video frame. One per fighter: it
## remembers each timed effect's full length, since the battle only keeps the ticks left.

## Badge order along the row.
const TIMED: Array[String] = ["brn", "par", "psn", "tox", "slp", "frz", "confusion",
	"reflect", "lightscreen", "auroraveil", "tailwind", "safeguard", "mist", "substitute", "ring", "charge"]
## Stat stages, in badge order after the timed effects.
const STAGES: Array[String] = ["atk", "def", "spa", "spd", "spe"]

## Full lengths in ticks, by effect, as last worked out.
var _totals := {}
## Ticks left at the last read, by effect, to tell a renewed effect from a running one.
var _lefts := {}


## The effects `fighter` shows now, in badge order: {"key", "left"} for a timed effect, with
## `left` the share of its time left, then {"key", "stages"} for each stat stage that isn't 0.
func read(fighter: Fighter) -> Array[Dictionary]:
	var ticks := {}
	if not fighter.status.is_empty():
		ticks[fighter.status] = fighter.status_ticks
	if fighter.confusion_ticks > 0:
		ticks.confusion = fighter.confusion_ticks
	var screens: Dictionary = fighter.arena.screens[fighter.side]
	for screen: String in screens:
		ticks[screen] = screens[screen]
	if fighter.substitute_ticks > 0:
		ticks.substitute = fighter.substitute_ticks
	if fighter.ring_ticks > 0:
		ticks.ring = fighter.ring_ticks
	if fighter.charged_ticks > 0:
		ticks.charge = fighter.charged_ticks
	var sides: Dictionary = fighter.arena.sides[fighter.side]
	for condition: String in sides:
		ticks[condition] = sides[condition]
	var entries: Array[Dictionary] = []
	for key in TIMED:
		if not ticks.has(key):
			_lefts.erase(key)
			continue
		var left: int = ticks[key]
		# A new or renewed effect: its full length is its standard one, or longer if more is
		# left (Light Clay's screens; sleep, whose length is rolled).
		if not _lefts.has(key) or left > _lefts[key]:
			_totals[key] = maxi(left, standard_ticks(key))
		_lefts[key] = left
		entries.append({"key": key, "left": clampf(float(left) / maxi(_totals[key], 1), 0.0, 1.0)})
	# Entry hazards on its side (team battles), with their layers: they last until cleared.
	var hazards: Dictionary = fighter.arena.hazards[fighter.side]
	for hazard: String in ArenaConditions.HAZARDS:
		if hazards.has(hazard):
			entries.append({"key": hazard, "layers": int(hazards[hazard])})
	if fighter.stockpile > 0:
		entries.append({"key": "stockpile", "layers": fighter.stockpile})
	for stat in STAGES:
		var stages: int = fighter.boosts[stat]
		if stages != 0:
			entries.append({"key": stat, "stages": stages})
	return entries


## An effect's usual length in ticks, or 0 when it varies (sleep).
static func standard_ticks(key: String) -> int:
	match key:
		"slp":
			return 0
		"frz":
			return Rules.seconds_to_ticks(Rules.FREEZE_SECONDS)
		"confusion":
			return Rules.seconds_to_ticks(Rules.CONFUSION_SECONDS)
		"reflect", "lightscreen", "auroraveil":
			return Rules.seconds_to_ticks(Rules.SCREEN_SECONDS)
		"tailwind", "safeguard", "mist":
			return ArenaConditions.field_ticks(key)
		"substitute", "ring", "charge":
			return Rules.seconds_to_ticks(Abilities.ABILITY_SECONDS)
	return Rules.seconds_to_ticks(Rules.STATUS_SECONDS)
