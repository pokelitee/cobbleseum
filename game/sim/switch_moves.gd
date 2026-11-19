class_name SwitchMoves
extends RefCounted
## Moves that switch fighters in team battles (concepts_brief.md §9.1, M18, rules version 41).
## A switch they make is free: it ignores the side's switch cooldown (and trapping, as in the main
## series) but, like any send-out, restarts it. With no one on the bench they do nothing more (the
## status ones fail), so one-on-one battles play them as plain hits.
## - Pivots: U-turn, Volt Switch and Flip Turn when they hit, Parting Shot (−1 Attack and Sp. Atk to
##   the foe), Teleport, Baton Pass (passing its stat stages, confusion and Substitute), Shed Tail
##   (half its max HP for a Substitute the newcomer keeps) and Chilly Reception (snow) when used:
##   the user is recalled for the side's pick, taken from its next "switch" intent within
##   Rules.PIVOT_SECONDS (else the first on the bench).
## - Phazers: Roar and Whirlwind when used, Dragon Tail and Circle Throw when they hit: the foe is
##   recalled for a random member of its bench.
## - Healing Wish and Lunar Dance: the user faints, and the next to come out in its place heals
##   half of max HP (the main series' full heal at Rules.HEAL_FACTOR) and loses its status.

## Status moves played as switches (BattleMove.Kind.CODED), and what each does: "pivot", "phaze"
## or "wish".
const CODED := {"partingshot": "pivot", "teleport": "pivot", "batonpass": "pivot", "shedtail": "pivot",
	"roar": "phaze", "whirlwind": "phaze", "healingwish": "wish", "lunardance": "wish"}
## Damaging moves that switch when they hit: the user ("pivot") or the target ("phaze").
const ON_HIT := {"uturn": "pivot", "voltswitch": "pivot", "flipturn": "pivot", "dragontail": "phaze", "circlethrow": "phaze"}
## Arena moves that also pivot.
const ARENA_PIVOTS: Array[String] = ["chillyreception"]
const SHED_TAIL_COST := 0.5
const SHED_TAIL_SUBSTITUTE := 0.25
const PARTING_SHOT := {"atk": -1, "spa": -1}
## The AIs' scores (StandInAI units): a pivot to a member that trades better, a phaze against a foe
## that has raised its stats or will take hazards, Baton Pass with stages worth passing, a wish
## when nearly knocked out with a hurt teammate to come.
const PIVOT_SCORE := 70.0
const PHAZE_SCORE := 70.0
const WISH_SCORE := 90.0
## A pivot is worth it to a member trading at least this much better (UtilityAI's switch margin).
const PIVOT_MARGIN := 0.2


## Whether `fighter`'s side has someone to switch in (teams[side] members not out and healthy).
static func bench(fighter: Fighter) -> int:
	return fighter.arena.bench[fighter.side]


## What a switching status move is worth to `me` now (StandInAI units). `gain` is how much better
## its side's best bench member trades against `foe` than `me` does (UtilityAI.switch_worth), or a
## negative number when it's worse or there's no bench.
static func score(me: Fighter, foe: Fighter, move: BattleMove, gain: float) -> float:
	var effect := str(CODED.get(move.id, ""))
	if effect == "phaze":
		if bench(foe) == 0:
			return 0.0
		var raised := 0
		for stat: String in foe.boosts:
			raised += maxi(0, int(foe.boosts[stat]))
		return PHAZE_SCORE if raised >= 2 or foe.arena.hazards_worth(foe.side) > 0.1 else 0.0
	if bench(me) == 0:
		return 0.0
	if effect == "wish":
		return WISH_SCORE if float(me.hp) / me.max_hp < StandInAI.SELF_DESTRUCT_BELOW else 0.0
	if move.id == "batonpass":
		var stages := 0
		for stat: String in me.boosts:
			stages += int(me.boosts[stat])
		return PIVOT_SCORE if stages >= 2 or (stages >= 0 and gain > PIVOT_MARGIN) else 0.0
	if move.id == "shedtail" and me.hp <= me.max_hp * SHED_TAIL_COST:
		return 0.0
	return PIVOT_SCORE if gain > PIVOT_MARGIN else 0.0
