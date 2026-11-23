class_name StatusMoves
extends RefCounted
## Status moves whose effect Showdown codes (concepts_brief.md §9.5, M18, rules version 39): odd
## self-buffs, moves that trade HP or stat stages, and Substitute. They're applied on release with
## no range, like a self-buff (BattleMove.Kind.CODED), except the heals, which are channels (§9.5).
## Readings:
## - HP paid for a lasting effect costs the main series' share (Belly Drum and Fillet Away half,
##   Clangorous Soul a third, Substitute a quarter); they fail if the user can't pay it.
## - Heals read like the other heals, at Rules.HEAL_FACTOR of the main series' amount.
## - Effects that last "until switched out" last Abilities.ABILITY_SECONDS (12 s), as for abilities.
## - Pain Split moves each fighter a sixth of the way to their average (Rules.HP_SHARE_READING).

## Moves played here (BattleMove.Kind.CODED); the heals among them are channels.
const CODED: Array[String] = ["bellydrum", "rest", "painsplit", "strengthsap", "wish", "healbell", "aromatherapy",
	"aquaring", "ingrain", "substitute", "focusenergy", "charge", "stockpile", "swallow", "psychup", "powerswap",
	"guardswap", "heartswap", "powersplit", "guardsplit", "topsyturvy", "acupressure", "takeheart"]
const HEALS: Array[String] = ["rest", "strengthsap", "swallow"]
## Self-buffs whose data the plain reading rejects (a stat drop, a volatile status alongside the
## boosts, an accuracy boost): their stat changes play as they are, accuracy left out.
const SELF_BUFFS: Array[String] = ["shellsmash", "noretreat", "clangoroussoul", "filletaway", "coil", "honeclaws",
	"defensecurl"]
## HP each costs, as a share of max HP (main-series shares, paid only while the user has more).
const HP_COSTS := {"bellydrum": 0.5, "filletaway": 0.5, "clangoroussoul": 1.0 / 3.0, "substitute": 0.25}
## Moves fired at the foe that both give a status and change its stats (Swagger, Flatter, Toxic
## Thread) or raise one stat and lower another (Spicy Extract): projectiles, as status moves are.
const MIXED_FOE: Array[String] = ["swagger", "flatter", "toxicthread", "spicyextract"]
## Rest heals its full amount (×Rules.HEAL_FACTOR), then the user sleeps this long.
const REST_SLEEP_SECONDS := 3.0
## Swallow heals by stockpiled count, Spit Up hits for 100 a count; Stockpile holds at most three.
const STOCKPILE_MAX := 3
const SWALLOW_SHARES: Array[float] = [0.0, 0.25, 0.5, 1.0]
const SPIT_UP_POWER := 100
## Wish lands Rules.DELAYED_SECONDS later on whoever is in the user's place, healing half of the
## user's max HP (×Rules.HEAL_FACTOR). Aqua Ring and Ingrain heal 1/16 a turn, read as a fifth of
## that each second (§9.9).
const WISH_SHARE := 0.5
const RING_HEAL := 1.0 / 80.0
## Strength Sap heals at most Recover's main-series half of max HP (before the heal factor): healing
## the foe's whole Attack, a third of max HP a use, it drew 6 of v39's first batch's 10 new draws.
const SAP_MOST := 0.5
## Focus Energy: critical hits 1 in 8, like Dragon Cheer. Charge: the next Electric move ×2.
const CHARGE_FACTOR := 2.0
## Acupressure raises a random stat by 2.
const ACUPRESSURE_STAGES := 2

## The AIs' scores (move-power units, StandInAI) and the moveset values (Movesets' scale). Rest
## sits below the utility threshold: valued like a big heal it filled 320 standard movesets, and
## 3 s asleep in real time costs more than the turn it costs in the main series.
const SUBSTITUTE_SCORE := 60.0
const RING_SCORE := 50.0
const FOCUS_SCORE := 50.0
const STAGE_SWING_SCORE := 30.0
const MOVESET_VALUES := {"bellydrum": 100.0, "rest": 75.0, "strengthsap": 90.0, "wish": 80.0, "painsplit": 60.0,
	"substitute": 70.0, "aquaring": 55.0, "ingrain": 55.0, "focusenergy": 60.0, "healbell": 50.0, "aromatherapy": 50.0,
	"takeheart": 85.0}
## Foe moves that mix a status with stat changes, valued below their plain kin: Swagger and Flatter
## hand the foe a boost, Spicy Extract raises its Attack.
const MIXED_FOE_VALUES := {"swagger": 35.0, "flatter": 35.0, "toxicthread": 65.0, "spicyextract": 30.0}
## A self-buff that also lowers a stat (Shell Smash) counts half a stage less per stage lost, and
## one that costs HP is worth this share for each share of max HP paid.
const LOST_STAGE_VALUE := 7.5
const HP_COST_VALUE := 0.8


## Whether `fighter` can use coded move `move` against `foe` now: it can pay any HP cost, Rest
## isn't kept off by its ability or the ground, a Substitute isn't already up, the stockpile has
## room or something to use.
static func usable(fighter: Fighter, foe: Fighter, move: BattleMove) -> bool:
	if HP_COSTS.has(move.id) and fighter.hp <= fighter.max_hp * float(HP_COSTS[move.id]):
		return false
	match move.id:
		"bellydrum":
			return fighter.boosts.atk < Rules.MAX_STAGE
		"rest":
			return fighter.hp < fighter.max_hp and not Abilities.status_immune(fighter, "slp") \
				and not fighter.arena.blocks_status(fighter, "slp")
		"substitute":
			return fighter.substitute_ticks == 0
		"stockpile":
			return fighter.stockpile < STOCKPILE_MAX
		"swallow", "spitup":
			return fighter.stockpile > 0
		"noretreat":
			return not fighter.no_retreat
	return true


## What a coded move is worth to the AIs now (StandInAI.move_score's units); 0 for nothing.
static func score(me: Fighter, foe: Fighter, move: BattleMove) -> float:
	if move.id in Volatiles.SELF_MOVES:
		return Volatiles.score(me, foe, move)
	# Switching moves need the bench's trades (UtilityAI); the stand-in AI never uses them.
	if SwitchMoves.CODED.has(move.id):
		return 0.0
	if not usable(me, foe, move):
		return 0.0
	var share := float(me.hp) / me.max_hp
	match move.id:
		"bellydrum":
			return StandInAI.BUFF_SCORE * 1.2 if share > 0.75 and me.stats.atk >= me.stats.spa else 0.0
		"rest":
			var hurt := 1.0 - share
			return StandInAI.HEAL_SCORE * hurt if share < 0.4 or (not me.status.is_empty() and share < 0.7) else 0.0
		"strengthsap", "wish":
			return StandInAI.HEAL_SCORE * (1.0 - share) if share < StandInAI.HEAL_BELOW and (move.id != "wish" or me.wish.is_empty()) else 0.0
		"swallow":
			return StandInAI.HEAL_SCORE * minf(1.0 - share, SWALLOW_SHARES[me.stockpile] * Rules.HEAL_FACTOR * 2.0) if share < StandInAI.HEAL_BELOW else 0.0
		"painsplit":
			var gap := float(foe.hp) / foe.max_hp - share
			return StandInAI.HEAL_SCORE * gap if gap > 0.2 else 0.0
		"healbell", "aromatherapy", "takeheart":
			var cured := not me.status.is_empty()
			if move.id == "takeheart":
				return StandInAI.BUFF_SCORE if cured or me.boosts.spa < StandInAI.STAGE_TARGET else 0.0
			return StandInAI.STATUS_SCORE if cured else 0.0
		"aquaring", "ingrain":
			return RING_SCORE if me.ring_ticks == 0 and share < 0.9 else 0.0
		"substitute":
			return SUBSTITUTE_SCORE if share > 0.5 else 0.0
		"focusenergy":
			return FOCUS_SCORE if me.cheer_ticks == 0 else 0.0
		"charge":
			var electric := me.moves.any(func(m: BattleMove) -> bool: return m.type == "Electric" and m.is_damaging())
			return StandInAI.BUFF_SCORE if electric and me.charged_ticks == 0 else 0.0
		"stockpile":
			return StandInAI.BUFF_SCORE * 0.5
		"psychup":
			return STAGE_SWING_SCORE * maxf(0.0, _stages(foe) - _stages(me))
		"topsyturvy":
			return STAGE_SWING_SCORE * maxf(0.0, _stages(foe)) * 2.0
		"powerswap", "guardswap", "heartswap":
			var stats: Array = {"powerswap": ["atk", "spa"], "guardswap": ["def", "spd"], "heartswap": BattleMove.STATS}[move.id]
			return STAGE_SWING_SCORE * maxf(0.0, _stages(foe, stats) - _stages(me, stats))
		"powersplit", "guardsplit":
			var stats: Array = ["atk", "spa"] if move.id == "powersplit" else ["def", "spd"]
			var mine := 0.0
			var theirs := 0.0
			for stat: String in stats:
				mine += me.stats[stat]
				theirs += foe.stats[stat]
			return StandInAI.BUFF_SCORE if theirs > mine * 1.3 else 0.0
		"acupressure":
			return StandInAI.BUFF_SCORE * 0.6
	return 0.0


## What a coded move is worth in a standard moveset (Movesets' scale), for a species attacking
## with `physical` stats.
static func moveset_value(move: BattleMove, physical: bool) -> float:
	if move.id in Volatiles.SELF_MOVES:
		return Volatiles.moveset_value(move, physical)
	if move.id == "bellydrum" and not physical:
		return 0.0
	# An HP cost is worth that much less, as for Fillet Away (Movesets.utility_value): at full
	# value Belly Drum took 25 standard movesets whose species won 34% (rules version 42).
	return float(MOVESET_VALUES.get(move.id, 0.0)) * (1.0 - HP_COST_VALUE * float(HP_COSTS.get(move.id, 0.0)))


## Stat stages summed (over `stats`, all by default).
static func _stages(fighter: Fighter, stats: Array = BattleMove.STATS) -> float:
	var total := 0
	for stat: String in stats:
		total += int(fighter.boosts[stat])
	return total
