class_name UtilityAI
extends RefCounted
## The utility AI (concepts_brief.md §11). Every decision it scores each candidate action
## (use a ready move, dodge, approach, back off, circle, hold) as the product of
## considerations, each a 0-1 value from a response curve, and takes the best.
## - Perception: it sees the opponent as it was `reaction_delay_ticks` ago (a buffer of
##   past states), and notices a projectile only once it has flown that long. Once it has
##   noticed an attack it judges the time left correctly.
## - Combining: products are compensated for the number of considerations, so actions
##   with more of them aren't penalised for it. A score of 0 vetoes the action.
## - Stability: the current action gets a commitment bonus, and movement is held for a
##   minimum time; between decisions (every `decision_interval_ticks`) it keeps moving.
## - How well it plays comes from the AIProfile: reaction delay, decision interval, the chance of
##   taking the second-best action, and the chance of dodging a given threat at all.
## - Guards: against a threat it may react to, it can raise a guard (if the profile's guard roll
##   for that threat succeeds) when the hit would land inside the guard's window from the front,
##   weighed against dodging: parrying melee pays most, and guarding saves dodge charges.
## - Feints (hard and ranked profiles): with the foe down to its last dodge charge (or out of
##   them with a guard ready), it may fake a melee or area wind-up to draw that dodge or guard,
##   then strike while the foe has neither left.
## - Spacing by style: the distance it keeps follows its melee lean (melee_lean), so kiters hold
##   their range and go in for melee only on an opening, and brawlers press in.
## - Doubles (M17): each fighter decides on its own but sees its ally. It picks its target by
##   the share of each foe's HP it could take, a focus bonus for its ally's target, closeness and
##   a pull to keep its lock; it watches every foe's wind-ups; a spread move counts every fighter
##   it would hit and is vetoed when it would hurt the ally more than the foes; and it keeps
##   apart from its ally.
## - Exact ties go to the side's random stream, never list order.
## With `keep_scores` set (the debug overlay), the last evaluation is kept in `last_scores`.

enum Action { USE_MOVE, DODGE, FEINT, GUARD, SWITCH, APPROACH, RETREAT, CIRCLE, HOLD, TAKE_COVER, FLANK }

## Movement scores stay below a usable attack's, so ready moves in range get used; the
## commitment bonus only steadies the choice between ways of moving.
const COMMITMENT_BONUS := 0.05
const MIN_HOLD_TICKS := 6
const HOLD_SCORE := 0.05
const CIRCLE_SCORE := 0.15
const WAITING_CIRCLE_BONUS := 0.2
## Move value (StandInAI.move_score, in move-power units) at which it saturates.
const VALUE_SCALE := 150.0
## Ticks ahead a projectile is checked for a hit.
const THREAT_HORIZON := 12
## The gap bands kept (§11, spacing by style). With a melee move ready and the fighter leaning
## melee, on an opening, or in overtime: just outside the foe's reach, inside dash range, so it
## closes only to strike. Otherwise with ranged moves ready, or waiting on cooldowns, a band
## blended by the melee lean from the kiter's (lean 0) to the brawler's (lean 1, pressing in).
## A kiter waiting farther out than this dragged battles into draws.
const MELEE_GAP := Vector2(1.8, 2.8)
const KITER_RANGED_GAP := Vector2(3.5, 6.0)
const BRAWLER_RANGED_GAP := Vector2(2.5, 4.5)
const KITER_WAITING_GAP := Vector2(3.0, 5.0)
const BRAWLER_WAITING_GAP := Vector2(2.2, 3.5)
## Below this melee lean a ready melee move pulls the fighter in only on an opening.
const KITER_LEAN := 0.5
## The lean of a fighter with no damaging move to weigh.
const NEUTRAL_LEAN := 0.5
## Each new strafe direction also shifts the band by up to this much, so distances vary.
const BAND_JITTER := 0.5
const STRAFE_MIN_TICKS := 30
const STRAFE_MAX_TICKS := 75
const STRAFE_WEIGHT := 0.8
const WALL_MARGIN := 1.5
const HISTORY := 32
## A heal's "cover" when the opponent could land a hit before the channel ends (and cancel it).
const EXPOSED := 0.15
## Terrain tactics (§9.8), only where the ground rises at least TACTICS_RELIEF somewhere:
## taking cover from a ranged attack it can't answer, and moving for a clear shot. Spots
## are looked for SPOT_DIRECTIONS ways at SPOT_DISTANCES; the foe's ranged attack counts as
## coming if it's ready within SHOT_SOON ticks.
const TACTICS_RELIEF := 1.0
const TAKE_COVER_SCORE := 0.45
const FLANK_SCORE := 0.5
const SPOT_DIRECTIONS := 16
const SPOT_DISTANCES: Array[float] = [1.5, 3.0]
const SHOT_SOON := 15
## A feint, once rolled for, outscores any attack: drawing the last dodge first is the point.
const FEINT_SCORE := 0.95
## Guards: how much a block is worth (a parry of a melee strike opens a punish window) and the
## ticks before a hit when raising the guard is best (it's up for Rules.GUARD_SECONDS).
const PARRY_REWARD := 1.0
const BLOCK_REWARD := 0.7
const GUARD_EARLIEST := 2
const GUARD_LATE_MARGIN := 3
const GUARD_OFF_TIMING := 0.6
## A move that would land while the foe it sees is still guarding scores this much.
const INTO_GUARD := 0.1
## A melee move into a foe whose ability or item punishes contact (Static, Rocky Helmet) scores
## this much.
const CONTACT_COST := 0.85
## Switching (team battles): a bench member's worth is its trade against the foe (the log of
## how much faster it would wear the foe down than be worn down), its HP first cut by what it
## would lose while landing. A switch is a chance worth rolling for once a member beats the
## fighter out by SWITCH_MARGIN (about a 1.5 times better trade); a rolled switch scores from
## SWITCH_BASE up by SWITCH_SLOPE per unit of gain, so a clear gain outscores most attacks.
const SWITCH_MARGIN := 0.4
const SWITCH_BASE := 0.6
const SWITCH_SLOPE := 0.3
const SWITCH_TOP := 0.95
## Doubles targeting: a foe's appeal is the share of its HP left the fighter's best move would
## take (up to 1), less TARGET_DISTANCE_COST a metre of gap, plus FOCUS_BONUS if the ally is on
## it and TARGET_STICK for the foe already locked, so the lock doesn't flicker.
const TARGET_DISTANCE_COST := 0.03
const FOCUS_BONUS := 0.15
const TARGET_STICK := 0.1
## A spread move's harm to the ally counts this many times its harm to a foe of the same share.
const ALLY_HARM_WEIGHT := 1.5
## Doubles spacing: within ALLY_SPACING metres of its ally a fighter edges away from it.
const ALLY_SPACING := 3.0
const ALLY_PUSH := 0.8
## Helping Hand is worth the most once the boost it adds would take this share of the target's
## max HP.
const HELPING_SHARE := 0.1

var profile: AIProfile
var random: SimRandom
var keep_scores := false
## The last evaluation when keep_scores is set: [{"action": String, "score": float,
## "considerations": {name: 0-1}}], best first.
var last_scores: Array[Dictionary] = []

## The opponent's recent states, a ring buffer of HISTORY entries.
var _history: Array[Dictionary] = []
var _history_count := 0
var _intent := {}
var _current := ""
var _held := 0
var _since_decision := 0
var _judged := {}
var _dodge_allowed := {}
var _guard_allowed := {}
var _strafe := 1.0
var _strafe_ticks := 0
var _band_shift := 0.0
## Where the chosen terrain tactic is heading (Vector2.INF for nowhere).
var _cover_spot := Vector2.INF
var _flank_spot := Vector2.INF
## This chance to feint's roll: -1 until rolled, then 0 (don't) or 1 (do). The chance lasts
## while the foe stays on its last dodge charge.
var _feint_roll := -1
## Switch chances rolled for, by "<own slot>><bench slot>@<foe slot>": true to take it.
var _switch_rolls := {}
## The fighters it last decided for and against; a team battle's send-out changes them.
var _me: Fighter
var _foe: Fighter
## Doubles: whether this battle is one, the recent states of every foe out (Fighter -> {"buffer":
## Array, "count": int}; singles keeps one buffer in _history), and the ally's position to keep
## apart from (Vector2.INF for none).
var _doubles := false
var _foe_histories := {}
## Off, it plays doubles as if each foe were alone (no target choice, ally or second foe), for
## probes measuring what the doubles play is worth.
var coordinate := true
var _ally_position := Vector2.INF

static var _curves := {}


func _init(ai_profile: AIProfile, stream: SimRandom) -> void:
	profile = ai_profile
	random = stream


## `index` is the fighter's in Battle.fighters (its side, in singles).
func decide(battle: Battle, index: int) -> Dictionary:
	var me := battle.fighters[index]
	var foe := battle.target_of(me)
	_doubles = battle.doubles and coordinate
	_meet(me, foe)
	if battle.is_waiting(index) and me.is_knocked_out():
		# Between Pokémon after a knockout: pick who comes out next.
		var pick := best_pick(battle, index)
		return {"switch": pick} if pick >= 0 else {}
	if battle.frozen(me) or me.is_knocked_out():
		_intent = {}
		return {}
	if _doubles:
		_remember_foes(battle, me)
		var ally := battle.ally_of(me)
		_ally_position = ally.position if not ally.is_knocked_out() else Vector2.INF
	else:
		_remember(foe)
	_held += 1
	_since_decision += 1
	if not me.can_act():
		_intent = {}
		return {}
	var keep_moving: bool = _intent.get("use", -1) < 0 and _intent.get("feint", -1) < 0 and _intent.get("dodge", Vector2.ZERO) == Vector2.ZERO \
		and not _intent.get("guard", false)
	if _since_decision < profile.decision_interval_ticks and keep_moving and not _intent.is_empty():
		return _around_terrain(battle, me, _movement_intent(me, _perceived(foe), _current))
	_since_decision = 0
	var retarget := -1
	if _doubles:
		var place := choose_target(battle, me)
		if place != me.target_place:
			retarget = place
			foe = battle.fighters[place * 2 + 1 - me.side]
			_meet(me, foe)
	var seen := _perceived(foe)
	var threat := _threat(battle, me, foe, seen)
	var candidates := _candidates(battle, me, foe, seen, threat)
	var choice := _choose(candidates)
	if choice.action != _current:
		_held = 0
	_current = choice.action
	match choice.kind:
		Action.USE_MOVE:
			_intent = {"use": choice.move}
		Action.DODGE:
			_intent = {"dodge": _dodge_direction(me, threat.direction)}
		Action.GUARD:
			_intent = {"guard": true}
		Action.FEINT:
			_intent = {"feint": choice.move}
		Action.SWITCH:
			_intent = {"switch": choice.move}
		_:
			_intent = _around_terrain(battle, me, _movement_intent(me, seen, _current))
	if retarget >= 0:
		_intent.target = retarget
	return _intent


## The place of the foe `me` should be locked onto in doubles (choose_target's appeal, best
## first; its current lock when no foe is up).
static func choose_target(battle: Battle, me: Fighter) -> int:
	var best := me.target_place
	var best_appeal := -INF
	var ally := battle.ally_of(me)
	var ally_target: Fighter = battle.target_of(ally) if ally != null and not ally.is_knocked_out() else null
	for foe in battle.out(1 - me.side):
		if foe.is_knocked_out():
			continue
		var reach := 0.0
		for move in me.moves:
			if move.is_damaging() and not move.self_destructs:
				reach = maxf(reach, expected_damage(me, foe, move, battle.data()))
		var appeal := minf(reach / maxf(foe.hp, 1.0), 1.0) - TARGET_DISTANCE_COST * Battle._gap(me, foe)
		if foe == ally_target:
			appeal += FOCUS_BONUS
		if foe.place == me.target_place:
			appeal += TARGET_STICK
		if appeal > best_appeal:
			best = foe.place
			best_appeal = appeal
	return best


## Starts afresh for a new fighter of its own (everything it was planning) or a new foe (what
## it remembers seeing), after a send-out.
func _meet(me: Fighter, foe: Fighter) -> void:
	if (_foe != null and foe != _foe) or (_me != null and me != _me):
		_switch_rolls.clear()
	if _doubles and _foe != null and foe != _foe:
		# Each foe keeps its own history in doubles, and threats are judged whoever made them;
		# only a feint's opening belongs to the foe it was rolled against.
		_feint_roll = -1
	elif _foe != null and foe != _foe:
		_history.clear()
		_history_count = 0
		_judged.clear()
		_dodge_allowed.clear()
		_guard_allowed.clear()
		_feint_roll = -1
	if _me != null and me != _me:
		_intent = {}
		_current = ""
		_held = 0
		_since_decision = 0
		_feint_roll = -1
		_cover_spot = Vector2.INF
		_flank_spot = Vector2.INF
	_me = me
	_foe = foe


## What one of doubles' ally moves is worth now, in move-value units (VALUE_SCALE at most); 0
## when it would do nothing (no ally up, or nothing to gain):
## - Helping Hand: half what the ally's best ready move would take from its target, with the
##   ally ready to use it and not already helped;
## - ally boosts and Dragon Cheer: a buff's worth while the ally can still use one;
## - Follow Me and Rage Powder: drawing attacks off an ally worn below half while this fighter
##   is still above half;
## - Wide Guard: while a foe it can see winds up a spread move that reaches its side;
## - team heals: a heal's worth for the HP both have lost.
static func ally_move_value(battle: Battle, me: Fighter, move: BattleMove) -> float:
	var ally := battle.ally_of(me)
	var ally_up := ally != null and not ally.is_knocked_out()
	if move.wide_guard:
		for foe in battle.out(1 - me.side):
			if foe.action != Fighter.Action.WINDUP or foe.is_knocked_out():
				continue
			var threat := foe.moves[foe.action_move]
			if threat.kind == BattleMove.Kind.AREA and (Battle._gap(foe, me) <= Rules.AREA_RADIUS
					or (ally_up and Battle._gap(foe, ally) <= Rules.AREA_RADIUS)):
				return VALUE_SCALE
		return 0.0
	if move.team_heal:
		var lost := 1.0 - float(me.hp) / me.max_hp
		if ally_up:
			lost += 1.0 - float(ally.hp) / ally.max_hp
		return StandInAI.HEAL_SCORE * minf(lost, 1.0) if lost > 1.0 - StandInAI.HEAL_BELOW else 0.0
	if not ally_up:
		return 0.0
	match move.kind:
		BattleMove.Kind.REDIRECT:
			var ally_share := float(ally.hp) / ally.max_hp
			var my_share := float(me.hp) / me.max_hp
			return StandInAI.HEAL_SCORE * (1.0 - ally_share) if ally_share < 0.5 and my_share > 0.5 else 0.0
		BattleMove.Kind.ALLY:
			if move.ally_effect == "helping":
				if ally.helping_ticks > 0 or not ally.can_act():
					return 0.0
				var best := 0.0
				var target := battle.target_of(ally)
				for i in ally.moves.size():
					if ally.move_ready(i) and ally.moves[i].is_damaging():
						best = maxf(best, expected_damage(ally, target, ally.moves[i], battle.data()))
				return VALUE_SCALE * minf(1.0, 0.5 * best / maxf(target.max_hp, 1.0) / HELPING_SHARE)
			if move.ally_effect == "cheer":
				return StandInAI.BUFF_SCORE if ally.cheer_ticks == 0 else 0.0
			for stat: String in move.boosts:
				if ally.boosts[stat] < StandInAI.STAGE_TARGET:
					return StandInAI.BUFF_SCORE
	return 0.0


## What a spread (area) move would do now in doubles: {"foes": how many foes it would hit,
## "share": the shares of their max HP it would take (×0.75 when it hits several) less
## ALLY_HARM_WEIGHT times the share of the ally's it would take}.
static func spread_value(battle: Battle, me: Fighter, move: BattleMove) -> Dictionary:
	var hit: Array[Fighter] = []
	var foes := 0
	for other in battle.fighters:
		if other == me or other.is_knocked_out() or (other.side == me.side and move.spread != "all"):
			continue
		# Telepathy keeps the ally out of its own side's spread moves.
		if other.side == me.side and other.ability_effect.get("ally_immune", false):
			continue
		if Battle._gap(me, other) <= Rules.AREA_RADIUS and absf(other.ground - me.ground) <= Rules.AREA_HEIGHT:
			hit.append(other)
			if other.side != me.side:
				foes += 1
	var factor := Rules.SPREAD_FACTOR if hit.size() > 1 else 1.0
	var share := 0.0
	for other in hit:
		var taken := expected_damage(me, other, move, battle.data()) * factor / maxf(other.max_hp, 1.0)
		share += taken if other.side != me.side else -ALLY_HARM_WEIGHT * taken
	return {"foes": foes, "share": share}


## Remembers how every foe out looks now (doubles), forgetting those no longer out.
func _remember_foes(battle: Battle, me: Fighter) -> void:
	var out := battle.out(1 - me.side)
	for known: Fighter in _foe_histories.keys():
		if not out.has(known):
			_foe_histories.erase(known)
	for foe in out:
		if not foe.is_knocked_out():
			_remember(foe)


## The intent's walking direction turned, if needed, so it doesn't run into ground the fighter
## can't climb (pillars, cliffs).
static func _around_terrain(battle: Battle, me: Fighter, intent: Dictionary) -> Dictionary:
	if intent.has("move"):
		intent.move = battle.terrain.steer(me.position, me.radius, me.ground, me.step_height(), intent.move)
	return intent


## Candidate actions with their considerations and scores, best first.
func _candidates(battle: Battle, me: Fighter, foe: Fighter, seen: Dictionary, threat: Dictionary) -> Array[Dictionary]:
	var gap := me.position.distance_to(seen.position) - me.radius - foe.radius
	# A threat only argues against committing to a move if the AI could dodge it instead.
	var can_avoid: bool = not threat.is_empty() and me.can_dodge() and _dodge_allowed.get(threat.key, false)
	var can_guard: bool = not threat.is_empty() and me.can_guard() and _guard_allowed.get(threat.key, false)
	var urgency := _urgency(threat.ticks) if can_avoid or can_guard else 0.0
	var candidates: Array[Dictionary] = []
	var any_ready := false
	# One line-of-sight check per decision (it's symmetric), shared by every move and tactic.
	var sight := battle.terrain.highest() <= 0.0 or battle.can_see(me, foe)
	for i in me.moves.size():
		if not me.move_ready(i) or not MoveEffects.usable(me, foe, me.moves[i]):
			continue
		any_ready = true
		var move := me.moves[i]
		var considerations := {
			# In range, and able to connect over the terrain (a clear line, a small height gap).
			"in_range": 1.0 if gap <= move.reach() and (sight if _needs_sight(move) else battle.can_reach(me, foe, move)) else 0.0,
			"safe_to_commit": 1.0 - 0.6 * urgency,
		}
		if move.is_damaging():
			# Expected damage covers power, STAB, stats, stages and type at once; the stand-in's
			# move value still vetoes self-destructing early and discounts charge, recharge and
			# self-lowering moves.
			# A Lightning Rod or Storm Drain foe draws the move to itself (doubles).
			var aim := battle.drawn_to(me, foe, move)
			var expected := expected_damage(me, aim, move, battle.data())
			# The stand-in's value already counts power the battle's state adds (MoveEffects), which
			# the expected damage counts too, so it's taken against that power.
			var adapted := MoveEffects.adapt(me, aim, move)
			var adjusted := StandInAI.move_score(me, aim, move) / maxf(adapted.power * move.expected_hits(), 1.0) if move.fixed_damage == 0 else 1.0
			var share := expected / maxf(aim.max_hp, 1.0)
			if _doubles and move.kind == BattleMove.Kind.AREA:
				var spread := spread_value(battle, me, move)
				share = spread.share
				considerations.in_range = 1.0 if spread.foes > 0 else 0.0
				if share <= 0.0:
					adjusted = 0.0
			# The stand-in's value of 0 is a veto (self-destructing early, sinking a stat below -2);
			# the damage curve's floor would otherwise turn it into a usable score.
			considerations.damage = _sample("damage", share * adjusted) if adjusted > 0.0 else 0.0
			considerations.finisher = _sample("finisher", expected / maxf(foe.hp, 1.0))
			if move.kind == BattleMove.Kind.MELEE and (Abilities.punishes_contact(foe) or Items.punishes_contact(foe)):
				considerations.contact_cost = CONTACT_COST
			if move.own_stat_drop() < 0 and _other_attack_on(me, i):
				considerations.stage_cost = stage_cost(me, move)
			# Focus Punch is a channel like a heal: only worth starting when it won't be hit first.
			if move.channels:
				considerations.cover = heal_cover(me, foe, seen, threat, move.windup_ticks)
		elif move.is_ally_move():
			considerations.value = _sample("value", ally_move_value(battle, me, move) / VALUE_SCALE)
			if move.kind == BattleMove.Kind.HEAL:
				considerations.cover = heal_cover(me, foe, seen, threat, move.windup_ticks)
		else:
			considerations.value = _sample("value", StandInAI.move_score(me, foe, move) / VALUE_SCALE)
			if move.kind == BattleMove.Kind.HEAL:
				considerations.cover = heal_cover(me, foe, seen, threat, move.windup_ticks)
		if not move.is_self() and _guarded_when_landing(me, seen, gap, move):
			considerations.into_guard = INTO_GUARD
		candidates.append(_scored("move:" + move.id, Action.USE_MOVE, considerations, i))
	_add_feint(battle, me, foe, gap, urgency, candidates)
	_add_switch(battle, me, foe, urgency, candidates)
	if can_avoid:
		candidates.append(_scored("dodge", Action.DODGE, {
			"urgency": urgency,
			"charges": _sample("charges", float(me.dodge_charges)),
			"danger": _sample("danger", threat.danger),
		}))
	if can_guard:
		var guard := guard_considerations(me, seen, threat)
		if not guard.is_empty():
			candidates.append(_scored("guard", Action.GUARD, guard))
	var band := _band(battle, me, foe, seen)
	candidates.append(_scored("approach", Action.APPROACH, {"too_far": _sample("too_far", gap - band.y)}))
	candidates.append(_scored("retreat", Action.RETREAT, {"too_close": _sample("too_close", band.x - gap)}))
	candidates.append(_scored("circle", Action.CIRCLE, {"base": CIRCLE_SCORE + (0.0 if any_ready else WAITING_CIRCLE_BONUS)}))
	candidates.append(_scored("hold", Action.HOLD, {"base": HOLD_SCORE}))
	_add_terrain_tactics(battle, me, foe, seen, gap, sight, candidates)
	for candidate in candidates:
		if candidate.action == _current and candidate.score > 0.0 and candidate.kind >= Action.APPROACH:
			candidate.score += COMMITMENT_BONUS
	return candidates


## A feint, when the foe is down to its last dodge charge: the first melee or area move that
## could be used for real (ready, in reach, able to connect). The chance is rolled once, when
## it comes up, with the profile's feint_chance: as soon as a move could be feinted, before it's
## in reach, so a fighter keeping its range knows to close in for the feint (_band).
func _add_feint(battle: Battle, me: Fighter, foe: Fighter, gap: float, urgency: float,
		candidates: Array[Dictionary]) -> void:
	# An opening: one way left to answer a strike, a dodge or else a guard.
	var opening := foe.dodge_charges == 1 or (foe.dodge_charges == 0 and foe.guard_cooldown == 0)
	if not opening or profile.feint_chance <= 0.0:
		_feint_roll = -1
		return
	for i in me.moves.size():
		var move := me.moves[i]
		if not me.can_feint(i):
			continue
		if _feint_roll < 0:
			_feint_roll = 1 if random.chance(profile.feint_chance) else 0
		if _feint_roll == 1 and gap <= move.reach() and battle.can_reach(me, foe, move):
			candidates.append(_scored("feint:" + move.id, Action.FEINT,
				{"base": FEINT_SCORE, "safe_to_commit": 1.0 - 0.6 * urgency}, i))
			return


## Terrain tactics, where the ground has relief: with no attack ready while the foe can see it
## and has a ranged attack coming, head for the nearest spot out of its sight; with a ranged
## move ready and in range but no clear line, head for the nearest spot with one.
func _add_terrain_tactics(battle: Battle, me: Fighter, foe: Fighter, seen: Dictionary, gap: float, exposed: bool,
		candidates: Array[Dictionary]) -> void:
	_cover_spot = Vector2.INF
	_flank_spot = Vector2.INF
	if battle.terrain.highest() < TACTICS_RELIEF:
		return
	var attack_ready := false
	var shot_ready := false
	for i in me.moves.size():
		var move := me.moves[i]
		if not me.move_ready(i):
			continue
		attack_ready = attack_ready or move.is_damaging()
		if _needs_sight(move) and gap <= move.reach():
			shot_ready = true
	var foe_shoots := false
	for i in foe.moves.size():
		if foe.moves[i].kind == BattleMove.Kind.PROJECTILE and foe.cooldowns[i] <= SHOT_SOON:
			foe_shoots = true
	var foe_eye := Vector3(seen.position.x, foe.ground + Rules.CHEST_HEIGHT, seen.position.y)
	if not attack_ready and foe_shoots and exposed:
		_cover_spot = find_spot(battle, me, foe_eye, false)
		if _cover_spot != Vector2.INF:
			candidates.append(_scored("take_cover", Action.TAKE_COVER, {"base": TAKE_COVER_SCORE}))
	if shot_ready and not exposed:
		_flank_spot = find_spot(battle, me, foe_eye, true)
		if _flank_spot != Vector2.INF:
			candidates.append(_scored("flank", Action.FLANK, {"base": FLANK_SCORE}))


static func _needs_sight(move: BattleMove) -> bool:
	return move.kind in [BattleMove.Kind.PROJECTILE, BattleMove.Kind.STATUS, BattleMove.Kind.DEBUFF]


## The nearest spot around `me` it can walk to (no climb beyond its reach, inside the wall)
## that `foe_eye` can see (`visible`) or can't: Vector2.INF if none.
static func find_spot(battle: Battle, me: Fighter, foe_eye: Vector3, visible: bool) -> Vector2:
	var terrain := battle.terrain
	for distance in SPOT_DISTANCES:
		for d in SPOT_DIRECTIONS:
			var angle := TAU * d / SPOT_DIRECTIONS
			var spot := me.position + Vector2(cos(angle), sin(angle)) * distance
			if spot.length() > Rules.ARENA_RADIUS - me.radius - 0.5:
				continue
			var ground := terrain.height_at(spot)
			if ground > me.ground + me.step_height():
				continue
			var chest := Vector3(spot.x, ground + Rules.CHEST_HEIGHT, spot.y)
			if terrain.clear_line(foe_eye, chest) == visible:
				return spot
	return Vector2.INF


## Picks from scored candidates: the best, ties broken at random, sometimes (a mistake) the
## second best, and movement held for MIN_HOLD_TICKS unless something better than moving comes up.
func _choose(candidates: Array[Dictionary]) -> Dictionary:
	if keep_scores:
		last_scores = candidates.duplicate()
		last_scores.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	var tied: Array[Dictionary] = []
	for candidate in candidates:
		if tied.is_empty() or candidate.score > tied[0].score and not is_equal_approx(candidate.score, tied[0].score):
			tied = [candidate]
		elif is_equal_approx(candidate.score, tied[0].score):
			tied.append(candidate)
	var best: Dictionary = tied[0] if tied.size() == 1 else tied[random.next_u32() % tied.size()]
	var second := {}
	for candidate in candidates:
		if not is_same(candidate, best) and (second.is_empty() or candidate.score > second.score):
			second = candidate
	if not second.is_empty() and second.score > 0.0 and random.chance(profile.mistake_chance):
		best = second
	var moving := [Action.APPROACH, Action.RETREAT, Action.CIRCLE, Action.HOLD, Action.TAKE_COVER, Action.FLANK]
	if _held < MIN_HOLD_TICKS and best.kind in moving and best.action != _current:
		for candidate in candidates:
			if candidate.action == _current:
				return candidate
	return best


func _scored(action: String, kind: Action, considerations: Dictionary, move := -1) -> Dictionary:
	return {"action": action, "kind": kind, "move": move, "considerations": considerations,
		"score": combine(considerations.values())}


## Product of considerations, compensated so more considerations don't drag scores down:
## each factor is lifted part of the way back towards 1 by (1 - 1/n).
static func combine(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var modification := 1.0 - 1.0 / values.size()
	var score := 1.0
	for value: float in values:
		var lifted := value + (1.0 - value) * modification * value
		score *= clampf(lifted, 0.0, 1.0)
	return score


## What a self-lowering move's drop costs the user's other attacks on that stat: the share of
## their power left after it (a boost thrown away counts in full).
static func stage_cost(me: Fighter, move: BattleMove) -> float:
	var stage: int = me.boosts[move.offensive_stat]
	return Rules.stage_multiplier(stage + move.own_stat_drop()) / Rules.stage_multiplier(stage)


## Whether the user has another damaging move that attacks with the same stat as move `index`.
static func _other_attack_on(me: Fighter, index: int) -> bool:
	var stat := me.moves[index].offensive_stat
	for i in me.moves.size():
		var other := me.moves[i]
		if i != index and other.is_damaging() and other.fixed_damage == 0 and not other.target_attacks and other.offensive_stat == stat:
			return true
	return false


## 1 if the opponent (as seen) can't land a hit within `channel` ticks, else EXPOSED: an
## incoming attack, or a damaging move it could ready, wind up and land in time.
static func heal_cover(me: Fighter, foe: Fighter, seen: Dictionary, threat: Dictionary, channel: int) -> float:
	if not threat.is_empty() and int(threat.ticks) <= channel:
		return EXPOSED
	if foe.is_incapacitated():
		return 1.0
	var busy := int(seen.action_ticks) if seen.action != Fighter.Action.READY else 0
	var gap := me.position.distance_to(seen.position) - me.radius - foe.radius
	var step := maxf(foe.current_move_speed() / Rules.TICK_RATE, 1e-6)
	for i in foe.moves.size():
		var move := foe.moves[i]
		if not move.is_damaging():
			continue
		var ticks := maxi(busy, foe.cooldowns[i]) + move.windup_ticks + maxf(gap - move.reach(), 0.0) / step
		if move.kind == BattleMove.Kind.PROJECTILE:
			ticks += gap / maxf(move.projectile_speed / Rules.TICK_RATE, 1e-6)
		if ticks < channel:
			return EXPOSED
	return 1.0


## Considerations for guarding against `threat`, or {} if the guard couldn't stop it: the hit
## must land inside the guard's window and come from the front (the guard turns to face the
## foe it sees).
static func guard_considerations(me: Fighter, seen: Dictionary, threat: Dictionary) -> Dictionary:
	var window := Rules.seconds_to_ticks(Rules.GUARD_SECONDS) - 1
	var ticks := float(threat.ticks)
	var to_foe := ((seen.position as Vector2) - me.position).normalized()
	var source := -(threat.direction as Vector2)
	if ticks < 0.0 or ticks > window or source.dot(to_foe) < cos(deg_to_rad(Rules.GUARD_ARC)):
		return {}
	var timing := 1.0 if ticks >= GUARD_EARLIEST and ticks <= window - GUARD_LATE_MARGIN else GUARD_OFF_TIMING
	return {
		"timing": timing,
		"danger": _sample("danger", threat.danger),
		"reward": PARRY_REWARD if threat.get("melee", false) else BLOCK_REWARD,
		"need": _sample("guard_need", float(me.dodge_charges)),
	}


## Whether `move`, used now, would land while the foe (as seen, a reaction delay ago) is still
## guarding: better to wait and hit its recovery.
func _guarded_when_landing(me: Fighter, seen: Dictionary, gap: float, move: BattleMove) -> bool:
	if seen.action != Fighter.Action.GUARD:
		return false
	var up := int(seen.action_ticks) - profile.reaction_delay_ticks - Rules.seconds_to_ticks(Rules.GUARD_RECOVERY)
	var lands := float(move.windup_ticks)
	if move.is_projectile():
		lands += gap / maxf(move.projectile_speed / Rules.TICK_RATE, 1e-6)
	return up > lands


## Damage `move` would do on average (no crit, mean roll, abilities included), for scoring.
static func expected_damage(attacker: Fighter, defender: Fighter, move: BattleMove, data: BattleData) -> float:
	if move.fixed_damage > 0:
		return move.fixed_damage * move.expected_hits()
	if not move.damage_rule.is_empty():
		return MoveEffects.rule_damage(attacker, defender, move)
	var parts := Battle.damage_parts(attacker, defender, move, data)
	return parts.base * parts.factor * parts.screen * (Rules.ROLL_MIN + Rules.ROLL_MAX) * 0.5 * move.expected_hits()


## Response curves, built once: input -> 0-1.
static func curve(name: String) -> Curve:
	if _curves.is_empty():
		_curves = {
			# Move value (share of VALUE_SCALE): anything useful scores, strong moves most.
			"value": _make(0.0, 1.0, [Vector2(0.0, 0.0), Vector2(0.15, 0.3), Vector2(0.6, 0.75), Vector2(1.0, 1.0)]),
			# Compressed type multiplier, 0.25 to 1.6.
			# Expected damage as a share of the foe's max HP. Even a weak hit beats doing
			# nothing, so the floor stays well above 0.
			"damage": _make(0.0, 0.4, [Vector2(0.0, 0.3), Vector2(0.05, 0.55), Vector2(0.15, 0.85), Vector2(0.4, 1.0)]),
			# Expected damage as a share of the foe's HP: a likely knockout scores highest.
			"finisher": _make(0.0, 1.0, [Vector2(0.0, 0.55), Vector2(0.5, 0.75), Vector2(1.0, 1.0)]),
			# Dodge charges left.
			"charges": _make(0.0, 2.0, [Vector2(0.0, 0.0), Vector2(1.0, 0.6), Vector2(2.0, 1.0)]),
			# Dodge charges left -> how much a guard is wanted instead: most with none to spare.
			"guard_need": _make(0.0, 2.0, [Vector2(0.0, 1.0), Vector2(1.0, 0.8), Vector2(2.0, 0.55)]),
			# Incoming damage as a share of our HP.
			"danger": _make(0.0, 0.5, [Vector2(0.0, 0.4), Vector2(0.25, 0.9), Vector2(0.5, 1.0)]),
			# Metres outside the preferred range.
			"too_far": _make(0.0, 6.0, [Vector2(0.0, 0.0), Vector2(1.0, 0.3), Vector2(4.0, 0.45), Vector2(6.0, 0.5)]),
			"too_close": _make(0.0, 3.0, [Vector2(0.0, 0.0), Vector2(1.0, 0.3), Vector2(3.0, 0.45)]),
		}
	return _curves[name]


static func _sample(name: String, input: float) -> float:
	var c := curve(name)
	return clampf(c.sample(clampf(input, c.min_domain, c.max_domain)), 0.0, 1.0)


static func _make(low: float, high: float, points: Array) -> Curve:
	var result := Curve.new()
	result.min_domain = low
	result.max_domain = high
	for point: Vector2 in points:
		result.add_point(point, 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return result


## Ticks until an attack lands -> 0-1: within 4 ticks it's urgent, from 12 it barely is.
static func _urgency(ticks: float) -> float:
	if ticks == INF:
		return 0.0
	return clampf(1.0 - (ticks - 4.0) / 8.0, 0.1, 1.0)


func _remember(foe: Fighter) -> void:
	var snapshot := {"position": foe.position, "action": foe.action, "action_ticks": foe.action_ticks,
		"action_move": foe.action_move}
	if _doubles:
		var entry: Dictionary = _foe_histories.get_or_add(foe, {"buffer": [], "count": 0})
		if entry.buffer.size() < HISTORY:
			entry.buffer.append(snapshot)
		else:
			entry.buffer[int(entry.count) % HISTORY] = snapshot
		entry.count += 1
		return
	if _history.size() < HISTORY:
		_history.append(snapshot)
	else:
		_history[_history_count % HISTORY] = snapshot
	_history_count += 1


## The opponent as this AI sees it: reaction_delay_ticks ago (or as early as remembered).
func _perceived(foe: Fighter) -> Dictionary:
	if _doubles:
		if not _foe_histories.has(foe):
			_remember(foe)
		var entry: Dictionary = _foe_histories[foe]
		var at := maxi(int(entry.count) - 1 - profile.reaction_delay_ticks, maxi(0, int(entry.count) - HISTORY))
		return entry.buffer[at % HISTORY]
	if _history_count == 0:
		_remember(foe)
	var index := maxi(_history_count - 1 - profile.reaction_delay_ticks, maxi(0, _history_count - HISTORY))
	return _history[index % HISTORY]


## The most urgent attack this AI has noticed: {"key", "direction", "ticks" (left until it
## lands), "danger" (share of our HP)} or {}. Each threat gets one dodge roll.
func _threat(battle: Battle, me: Fighter, foe: Fighter, seen: Dictionary) -> Dictionary:
	var data := battle.data()
	var best := {}
	var delay := profile.reaction_delay_ticks
	for projectile in battle.projectiles:
		if int(projectile.owner) == me.side or projectile.get("dodged", false):
			continue
		var velocity: Vector2 = projectile.velocity
		var speed := maxf(velocity.length(), 1e-6)
		if float(projectile.travelled) / speed < delay:
			continue  # not noticed yet
		var start: Vector2 = projectile.position
		var t := (me.position - start).dot(velocity) / (speed * speed)
		if t < 0.0 or t > THREAT_HORIZON:
			continue
		if (start + velocity * t).distance_to(me.position) > me.radius + Rules.PROJECTILE_RADIUS:
			continue
		# A projectile aimed at the ally flies past this fighter.
		if _doubles and int(projectile.get("target", -1)) != Battle.index_of(me):
			continue
		var shooter: Fighter = battle.teams[projectile.owner][projectile.slot]
		var move := shooter.moves[projectile.move]
		var threat := {"key": "p%d" % int(projectile.id),
			"direction": velocity.normalized(), "ticks": t, "melee": false,
			"danger": expected_damage(shooter, me, move, data) / maxf(me.hp, 1.0) if move.is_damaging() else 0.1}
		if best.is_empty() or threat.ticks < best.ticks:
			best = threat
	# A Future Sight about to land on this fighter's place is dodged like any other hit.
	for member: Fighter in battle.teams[1 - me.side]:
		if member.foresight.is_empty() or int(member.foresight.target) != Battle.index_of(me):
			continue
		var ticks := float(int(member.foresight.ticks))
		if ticks > THREAT_HORIZON:
			continue
		var move := member.moves[int(member.foresight.move)]
		var threat := {"key": "f%d.%d" % [member.slot, battle.tick + int(member.foresight.ticks)],
			"direction": (me.position - member.position).normalized(), "ticks": ticks, "melee": false,
			"danger": expected_damage(member, me, move, data) / maxf(me.hp, 1.0)}
		if best.is_empty() or threat.ticks < best.ticks:
			best = threat
	var attackers: Array[Fighter] = [foe]
	if _doubles:
		attackers = []
		for other in battle.out(1 - me.side):
			if not other.is_knocked_out():
				attackers.append(other)
	for attacker in attackers:
		var view := seen if attacker == foe else _perceived(attacker)
		if view.action != Fighter.Action.WINDUP:
			continue
		var move := attacker.moves[view.action_move]
		# In doubles a melee strike only threatens the fighter it's aimed at (a foe's own target).
		if _doubles and move.kind == BattleMove.Kind.MELEE and battle.target_of(attacker) != me:
			continue
		var reach := Rules.MELEE_DASH_RANGE if move.kind == BattleMove.Kind.MELEE else Rules.AREA_RADIUS
		var gap := me.position.distance_to(view.position) - me.radius - attacker.radius
		if (move.kind == BattleMove.Kind.MELEE or move.kind == BattleMove.Kind.AREA) and gap <= reach:
			var started := battle.tick - delay - (move.windup_ticks - int(view.action_ticks))
			var key := "w%d" % started if not _doubles else "w%d.%d" % [started, Battle.index_of(attacker)]
			var threat := {"key": key, "direction": (me.position - view.position).normalized(),
				"melee": move.kind == BattleMove.Kind.MELEE,
				"ticks": float(int(view.action_ticks) - delay), "danger": expected_damage(attacker, me, move, data) / maxf(me.hp, 1.0)}
			# A wind-up that has already landed by the time the AI sees it start is no threat.
			if threat.ticks >= 0.0 and (best.is_empty() or threat.ticks < best.ticks):
				best = threat
	if not best.is_empty() and not _judged.has(best.key):
		_judged[best.key] = true
		_dodge_allowed[best.key] = random.chance(profile.dodge_chance)
		_guard_allowed[best.key] = _dodge_allowed[best.key] and profile.guard_chance > 0.0 and random.chance(profile.guard_chance)
	return best


## The gap to keep, from the fighter's style and the moves that are ready. A ready melee or area
## move brings it close if it leans melee, or on an opening; otherwise it keeps the ranged band
## (projectiles ready) or the waiting band, each blended by its melee lean. In overtime everyone
## closes in for a ready melee move, so kiting doesn't run out the clock.
func _band(battle: Battle, me: Fighter, foe: Fighter, seen: Dictionary) -> Vector2:
	var melee := false
	var ranged := false
	for i in me.moves.size():
		if not me.move_ready(i) or not me.moves[i].is_damaging():
			continue
		if me.moves[i].kind == BattleMove.Kind.PROJECTILE:
			ranged = true
		else:
			melee = true
	var lean := melee_lean(me, foe, battle.data())
	var overtime := battle.tick >= battle.overtime_tick
	var close := melee and (lean >= KITER_LEAN or overtime or _opening(foe, seen))
	var band: Vector2
	if close:
		band = MELEE_GAP
	elif ranged:
		band = KITER_RANGED_GAP.lerp(BRAWLER_RANGED_GAP, lean)
	else:
		band = KITER_WAITING_GAP.lerp(BRAWLER_WAITING_GAP, lean)
	band += Vector2.ONE * _band_shift
	if close:
		band.y = minf(band.y, Rules.MELEE_DASH_RANGE - 0.2)
	return band


## How much the fighter leans melee against this foe, 0-1: its close moves' (melee and area)
## share of the expected damage per second of its whole moveset, ready or not. Expected damage
## covers its attacking stats, STAB, the foe's defences and type, and stat stages, so the lean
## shifts as boosts and drops come and go. Self-destructing moves don't count.
## A switch to the bench member with the best worth (switch_worth), if it beats the fighter out
## by SWITCH_MARGIN and the profile's roll for that chance succeeded.
func _add_switch(battle: Battle, me: Fighter, foe: Fighter, urgency: float, candidates: Array[Dictionary]) -> void:
	if profile.switch_chance <= 0.0 or battle.teams[me.side].size() < 2:
		return
	var best := -1
	var best_gain := SWITCH_MARGIN
	var staying := trade(me, foe, battle.data())
	for member: Fighter in battle.healthy(me.side):
		if not battle.can_switch(Battle.index_of(me), member.slot):
			continue
		var gain := switch_worth(member, foe, battle.data()) - staying
		if gain > best_gain:
			best = member.slot
			best_gain = gain
	if best < 0:
		return
	var key := "%d>%d@%d" % [me.slot, best, foe.slot]
	if not _switch_rolls.has(key):
		_switch_rolls[key] = random.chance(profile.switch_chance)
	if not _switch_rolls[key]:
		return
	candidates.append(_scored("switch:%d" % best, Action.SWITCH, {
		"gain": minf(SWITCH_BASE + SWITCH_SLOPE * best_gain, SWITCH_TOP),
		"safe_to_commit": 1.0 - 0.6 * urgency,
	}, best))


## A bench member's worth against `foe`: its trade with the HP it would lose while it lands
## (Rules.SWITCH_SECONDS) taken off.
static func switch_worth(member: Fighter, foe: Fighter, data: BattleData) -> float:
	var landing := damage_rate(foe, member, data) * Rules.SWITCH_SECONDS
	return trade(member, foe, data, member.hp - landing)


## How `me` fares against `foe`: the log of the share of the foe's HP it takes a second over the
## share of its own HP (`hp`, its current HP by default) it loses a second to the foe's attacks
## and its status condition. 0 is an even trade; each 0.7 doubles it. Its stat stages, HP and
## status count, so a fighter that has been worn down or has dropped its stats fares worse.
static func trade(me: Fighter, foe: Fighter, data: BattleData, hp := -1.0) -> float:
	var dealt := damage_rate(me, foe, data) / maxf(foe.hp, 1.0)
	var taken := (damage_rate(foe, me, data) + status_rate(me)) / maxf(hp if hp >= 0.0 else float(me.hp), 1.0)
	return log(maxf(dealt, 1e-6) / maxf(taken, 1e-6))


## Expected damage a second from `attacker`'s damaging moves against `defender`, each at the rate
## its wind-up, recovery and cooldown allow (as melee_lean weighs them).
static func damage_rate(attacker: Fighter, defender: Fighter, data: BattleData) -> float:
	var rate := 0.0
	for move in attacker.moves:
		if not move.is_damaging() or move.self_destructs:
			continue
		var cycle := maxf(move.windup_ticks + move.recovery_ticks + move.cooldown_ticks, 1.0)
		rate += expected_damage(attacker, defender, move, data) / cycle
	return rate * Rules.TICK_RATE


## HP a second `fighter` loses to its status condition.
static func status_rate(fighter: Fighter) -> float:
	match fighter.status:
		"brn":
			return fighter.max_hp * Rules.BURN_DAMAGE
		"psn":
			return 0.0 if fighter.ability_effect.get("poison_heal", false) else fighter.max_hp * Rules.POISON_DAMAGE
		"tox":
			return 0.0 if fighter.ability_effect.get("poison_heal", false) else fighter.max_hp * Rules.TOXIC_STEP * (fighter.toxic_level + 1)
	return 0.0


## The team slot the place `index` (Battle.index_of; a side in singles) should send out after a
## knockout: the bench member with the best trade against the foe it will face, or -1 when no
## one is left.
static func best_pick(battle: Battle, index: int) -> int:
	var side := index % 2
	var foe := battle.target_of(battle.fighters[index])
	var best := -1
	var best_worth := -INF
	for member: Fighter in battle.healthy(side):
		if battle.fighters.has(member):
			continue
		var worth := trade(member, foe, battle.data()) if not foe.is_knocked_out() else float(member.hp) / member.max_hp
		if worth > best_worth:
			best = member.slot
			best_worth = worth
	return best


static func melee_lean(me: Fighter, foe: Fighter, data: BattleData) -> float:
	var close := 0.0
	var total := 0.0
	for move in me.moves:
		if not move.is_damaging() or move.self_destructs:
			continue
		var cycle := maxf(move.windup_ticks + move.recovery_ticks + move.cooldown_ticks, 1.0)
		var rate := expected_damage(me, foe, move, data) / cycle
		total += rate
		if move.kind != BattleMove.Kind.PROJECTILE:
			close += rate
	return close / total if total > 0.0 else NEUTRAL_LEAN


## Whether a fighter keeping its range should go in for a melee strike: the foe (as seen) is
## recovering, asleep, frozen or stunned, or has no dodge and no guard ready, or this AI has
## rolled to feint (it closes in for the feint).
func _opening(foe: Fighter, seen: Dictionary) -> bool:
	return seen.action == Fighter.Action.RECOVERY or foe.is_incapacitated() \
		or (foe.dodge_charges == 0 and foe.guard_cooldown > 0) or _feint_roll == 1


func _movement_intent(me: Fighter, seen: Dictionary, action: String) -> Dictionary:
	_strafe_ticks -= 1
	if _strafe_ticks <= 0:
		_strafe = 1.0 if random.chance(0.5) else -1.0
		# Agile species switch sides sooner, so they dart rather than orbit.
		_strafe_ticks = roundi((STRAFE_MIN_TICKS + int(random.next_u32() % (STRAFE_MAX_TICKS - STRAFE_MIN_TICKS + 1))) / me.current_agility())
		_band_shift = (random.next_float() * 2.0 - 1.0) * BAND_JITTER
	var toward: Vector2 = ((seen.position as Vector2) - me.position).normalized()
	var side := Vector2(-toward.y, toward.x) * _strafe
	var direction := Vector2.ZERO
	match action:
		"approach":
			direction = toward + side * 0.3
		"retreat":
			direction = -toward + side * 0.5
		"circle":
			direction = side * STRAFE_WEIGHT
		"take_cover", "flank":
			var spot := _cover_spot if action == "take_cover" else _flank_spot
			if spot == Vector2.INF:
				return {"move": Vector2.ZERO}
			direction = spot - me.position
		_:
			return {"move": Vector2.ZERO}
	if me.position.length() > Rules.ARENA_RADIUS - me.radius - WALL_MARGIN:
		direction += -me.position.normalized()
		if side.dot(-me.position) < 0.0:
			_strafe = -_strafe
	if _doubles and _ally_position != Vector2.INF:
		var from_ally := me.position - _ally_position
		var apart := from_ally.length()
		if apart < ALLY_SPACING and apart > 1e-4:
			direction += from_ally / apart * ALLY_PUSH * (1.0 - apart / ALLY_SPACING)
	return {"move": direction.normalized() if direction.length_squared() > 0.0 else Vector2.ZERO}


## Sideways to the threat: towards the centre near the wall, else a random side.
func _dodge_direction(me: Fighter, threat: Vector2) -> Vector2:
	var side := Vector2(-threat.y, threat.x)
	if me.position.length() > Rules.ARENA_RADIUS - WALL_MARGIN - Rules.DODGE_DISTANCE:
		return side if side.dot(-me.position) >= 0.0 else -side
	return side if random.chance(0.5) else -side
