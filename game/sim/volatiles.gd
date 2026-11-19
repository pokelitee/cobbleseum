class_name Volatiles
extends RefCounted
## Lingering effects on one fighter (concepts_brief.md §9.5, M18, rules version 40), the main
## series' volatile statuses: Fighter.volatiles holds each one's ticks left, Fighter.volatile_data
## what it needs (the seeder, the move disabled, the types to go back to). They all end when the
## fighter is recalled. Readings follow §9.9: a turn reads as 4 s (`TURN_SECONDS`), "until switched
## out" as Abilities.ABILITY_SECONDS (12 s), and per-turn HP shares run at a fifth a second.
##
## From status moves fired at the foe (projectiles, as status moves are):
## - taunt (no status-category moves), encore (only the move it last used), disable (that move
##   blocked), torment (not the same move twice running), heal block (no heals), trapped (Block,
##   Mean Look, Spider Web: no switching), octolock (trapped, and −1 Defense and Sp. Def a turn);
## - leechseed (1/40 of max HP a second drained to the seeder's place; Grass types are immune),
##   yawn (falls asleep a turn later), tarshot (−1 Speed, Fire moves twice as effective);
## - new types (Soak, Magic Powder, Forest's Curse adds Grass) or abilities (Worry Seed: Insomnia,
##   Gastro Acid: none, Entrainment: the user's, Skill Swap: swapped).
## From damaging moves on hit: bound (Bind, Wrap, Fire Spin and kin: 1/40 a second, trapped),
## saltcure (1/40 a second, 1/20 for Water and Steel types), smackdown (grounded), trapped (Spirit
## Shackle, Anchor Shot; Jaw Lock both), heal block (Psychic Noise, 2 turns), throatchop (no sound
## moves, 2 turns), syrupbomb (−1 Speed a turn, 3 turns); on the user, glaiverush (hits on it ×2
## until it moves again, read as Rules.RECENT_SECONDS) and uproar (nobody falls asleep, 3 turns).
## From the user's own moves: curse (a Ghost type pays half its max HP to curse the foe, 1/20 a
## second; others +1 Attack and Defense, −1 Speed), destinybond (a foe that knocks it out in the
## next Rules.RECENT_SECONDS faints too), perish (Perish Song: every fighter out faints in 3 turns
## unless recalled; Soundproof is immune), magnetrise (airborne, 5 turns), imprison (foes can't use
## the moves it knows), and new types (Conversion: its first move's, Reflect Type: the foe's) or
## abilities (Role Play: the foe's).

const TURN_SECONDS := 4.0
## Status moves fired at the foe, by the effect they leave.
const FOE_MOVES := {"taunt": "taunt", "encore": "encore", "disable": "disable", "torment": "torment",
	"healblock": "healblock", "block": "trapped", "meanlook": "trapped", "spiderweb": "trapped", "octolock": "octolock",
	"leechseed": "leechseed", "yawn": "yawn", "tarshot": "tarshot", "soak": "types", "magicpowder": "types",
	"forestscurse": "types", "trickortreat": "types", "worryseed": "ability", "gastroacid": "ability",
	"entrainment": "ability", "skillswap": "ability"}
## Damaging moves that leave an effect on the target when they hit (or, "self:", on the user).
const ON_HIT := {"bind": "bound", "wrap": "bound", "firespin": "bound", "whirlpool": "bound", "sandtomb": "bound",
	"infestation": "bound", "magmastorm": "bound", "thundercage": "bound", "snaptrap": "bound", "saltcure": "saltcure",
	"smackdown": "smackdown", "thousandarrows": "smackdown", "spiritshackle": "trapped", "anchorshot": "trapped",
	"jawlock": "trapped", "psychicnoise": "healblock", "throatchop": "throatchop", "syrupbomb": "syrupbomb",
	"glaiverush": "self:glaiverush", "uproar": "self:uproar"}
## The user's own moves (BattleMove.Kind.CODED).
const SELF_MOVES: Array[String] = ["curse", "destinybond", "perishsong", "magnetrise", "imprison", "conversion",
	"reflecttype", "roleplay"]
## Seconds each effect lasts (Abilities.ABILITY_SECONDS when not listed).
const SECONDS := {"disable": 16.0, "yawn": 4.0, "healblock": 12.0, "throatchop": 8.0, "glaiverush": 3.0,
	"destinybond": 3.0, "magnetrise": 20.0, "syrupbomb": 12.0}
## Types the type-changing moves give: a set, or "+Type" to add one.
const NEW_TYPES := {"soak": ["Water"], "magicpowder": ["Psychic"], "forestscurse": ["+Grass"], "trickortreat": ["+Ghost"]}
## Abilities the ability-changing moves give the target.
const NEW_ABILITIES := {"worryseed": "insomnia", "gastroacid": ""}
## HP shares a second: Leech Seed and binding 1/8 a turn, Curse 1/4, Salt Cure 1/8 (1/4 for Water
## and Steel), at a fifth a second.
const DRAIN := {"leechseed": 1.0 / 40.0, "bound": 1.0 / 40.0, "curse": 1.0 / 20.0, "saltcure": 1.0 / 40.0}
const SALT_WEAK: Array[String] = ["Water", "Steel"]
## Effects that keep a fighter from being switched out.
const TRAPPING: Array[String] = ["trapped", "bound", "octolock"]
## Hits on a fighter after Glaive Rush deal this much more.
const GLAIVE_FACTOR := 2.0
## The AIs' scores (StandInAI units) and the moveset values (Movesets' scale) of the status moves.
const SCORES := {"taunt": 60.0, "encore": 70.0, "disable": 50.0, "torment": 30.0, "trapped": 0.0, "octolock": 60.0,
	"leechseed": 90.0, "yawn": 90.0, "tarshot": 40.0, "healblock": 40.0, "magnetrise": 60.0, "destinybond": 90.0,
	"perishsong": 70.0, "imprison": 40.0, "curse": 80.0}
## The type- and ability-changing moves (valued by the utility AI, UtilityAI.change_value; the
## stand-in AI never uses them), by the effect they leave; an ability worth at least STRONG_ABILITY
## in its table is worth taking away.
const CHANGERS := {"soak": "types", "magicpowder": "types", "forestscurse": "types", "trickortreat": "types",
	"conversion": "types", "reflecttype": "types", "worryseed": "ability", "gastroacid": "ability",
	"entrainment": "ability", "skillswap": "ability", "roleplay": "ability"}
const ABILITY_SCORE := 50.0
const STRONG_ABILITY := 6.0
const MOVESET_VALUES := {"taunt": 60.0, "encore": 50.0, "disable": 40.0, "torment": 30.0, "leechseed": 90.0, "yawn": 85.0,
	"curse": 70.0, "destinybond": 50.0, "magnetrise": 50.0, "octolock": 60.0, "tarshot": 30.0}


## Ticks effect `name` lasts.
static func ticks_for(name: String) -> int:
	return Rules.seconds_to_ticks(float(SECONDS.get(name, Abilities.ABILITY_SECONDS)))


## Whether `fighter`'s effects (and its foes' Imprison) let it use `move` now.
static func allows(fighter: Fighter, move: BattleMove) -> bool:
	var on := fighter.volatiles
	if on.has("taunt") and not move.is_damaging():
		return false
	if on.has("encore") and move.id != str(fighter.volatile_data.get("encore", move.id)):
		return false
	if on.has("disable") and move.id == str(fighter.volatile_data.get("disable", "")):
		return false
	if on.has("torment") and move.id == fighter.last_move:
		return false
	if on.has("healblock") and (move.kind == BattleMove.Kind.HEAL or move.id in StatusMoves.HEALS or move.drain_share > 0.0):
		return false
	if on.has("throatchop") and move.flags.has("sound"):
		return false
	if move.id == "destinybond" and fighter.last_move == "destinybond":
		return false
	return true


## Whether a foe of `fighter` with Imprison up knows `move` (so `fighter` can't use it).
static func imprisoned(foes: Array, move: BattleMove) -> bool:
	for foe: Fighter in foes:
		if foe.volatiles.has("imprison") and foe.moves.any(func(m: BattleMove) -> bool: return m.id == move.id):
			return true
	return false


## Whether `fighter` is kept from being switched out.
static func trapped(fighter: Fighter) -> bool:
	for name in TRAPPING:
		if fighter.volatiles.has(name):
			return true
	return false


## The share of max HP effect `name` takes from `fighter` each second (0 for none).
static func drain(fighter: Fighter, name: String) -> float:
	var share := float(DRAIN.get(name, 0.0))
	if name == "saltcure" and SALT_WEAK.any(func(type: String) -> bool: return type in fighter.types):
		share *= 2.0
	return share


## Whether `target` can be given effect `name` by `move` now: not one it already has, Leech Seed
## not on a Grass type, Yawn not on one with a status, Encore and Disable only after it has used a
## move, ability changes only to abilities in the table.
static func can_give(target: Fighter, name: String, move_id: String, user: Fighter) -> bool:
	if target.volatiles.has(name) and name != "types" and name != "ability":
		return false
	match name:
		"leechseed":
			return not "Grass" in target.types
		"yawn":
			return target.status.is_empty()
		"encore", "disable":
			return not target.last_move.is_empty()
		"ability":
			if move_id == "entrainment":
				return user.ability != target.ability
			if move_id == "skillswap":
				return user.ability != target.ability
			return target.ability != str(NEW_ABILITIES.get(move_id, ""))
		"perish":
			return not target.ability_effect.get("immune_flags", []).has("sound")
	return true


## What a lingering status move is worth to the AIs now (StandInAI units); 0 for nothing.
static func score(me: Fighter, foe: Fighter, move: BattleMove) -> float:
	var name := str(FOE_MOVES.get(move.id, move.id))
	var share := float(me.hp) / me.max_hp
	match move.id:
		"curse":
			if "Ghost" in me.types:
				return SCORES.curse if share > 0.6 and not foe.volatiles.has("curse") else 0.0
			return StandInAI.BUFF_SCORE if me.stats.atk >= me.stats.spa and me.boosts.atk < StandInAI.STAGE_TARGET else 0.0
		"destinybond":
			return SCORES.destinybond if share < 0.2 and me.last_move != "destinybond" else 0.0
		"perishsong":
			# Only worth it with more of its team left than the foe's (it takes both out).
			return SCORES.perishsong if me.arena.bench[me.side] > me.arena.bench[foe.side] else 0.0
		"magnetrise":
			var ground := foe.moves.any(func(m: BattleMove) -> bool: return m.type == "Ground" and m.is_damaging())
			return SCORES.magnetrise if ground and not me.volatiles.has("magnetrise") and ArenaConditions.grounded(me) else 0.0
		"imprison":
			var shared := foe.moves.any(func(m: BattleMove) -> bool: return me.moves.any(func(n: BattleMove) -> bool: return n.id == m.id and n != move))
			return SCORES.imprison if shared and not me.volatiles.has("imprison") else 0.0
		"taunt":
			var status := foe.moves.any(func(m: BattleMove) -> bool: return not m.is_damaging())
			return SCORES.taunt if status and not foe.volatiles.has("taunt") else 0.0
		"encore":
			var last := _move_named(foe, foe.last_move)
			return SCORES.encore if last != null and not last.is_damaging() and not foe.volatiles.has("encore") else 0.0
		"disable":
			var last := _move_named(foe, foe.last_move)
			return SCORES.disable if last != null and last.is_damaging() and not foe.volatiles.has("disable") else 0.0
		"healblock":
			var heals := foe.moves.any(func(m: BattleMove) -> bool: return m.kind == BattleMove.Kind.HEAL or m.id in StatusMoves.HEALS)
			return SCORES.healblock if heals and not foe.volatiles.has("healblock") else 0.0
	if not FOE_MOVES.has(move.id) or not can_give(foe, name, move.id, me) or name in ["types", "ability"]:
		return 0.0
	if name == "trapped":
		return 0.0
	if name == "yawn" and (Abilities.status_immune(foe, "slp") or me.arena.blocks_status(foe, "slp")):
		return 0.0
	return float(SCORES.get(name, 0.0))


static func _move_named(fighter: Fighter, id: String) -> BattleMove:
	for move in fighter.moves:
		if move.id == id:
			return move
	return null


## What a lingering status move is worth in a standard moveset.
static func moveset_value(move: BattleMove, physical: bool) -> float:
	if move.id == "curse":
		return float(MOVESET_VALUES.curse) if physical else 0.0
	return float(MOVESET_VALUES.get(move.id, 0.0))
