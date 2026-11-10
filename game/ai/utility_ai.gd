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
## - Difficulty comes from the AIProfile: reaction delay, decision interval, the chance of
##   taking the second-best action, and the chance of dodging a given threat at all.
## - Exact ties go to the side's random stream, never list order.
## With `keep_scores` set (the debug overlay), the last evaluation is kept in `last_scores`.

enum Action { USE_MOVE, DODGE, APPROACH, RETREAT, CIRCLE, HOLD }

## Movement scores stay below a usable attack's, so ready moves in range get used; the
## commitment bonus only steadies the choice between ways of moving.
const COMMITMENT_BONUS := 0.05
const MIN_HOLD_TICKS := 6
const HOLD_SCORE := 0.05
const CIRCLE_SCORE := 0.15
const WAITING_CIRCLE_BONUS := 0.2
## Move value (SimpleAI.move_score, in move-power units) at which it saturates.
const VALUE_SCALE := 150.0
## Ticks ahead a projectile is checked for a hit, and the gap bands kept while ranged moves
## are ready and while waiting on cooldowns.
const THREAT_HORIZON := 12
const RANGED_GAP := Vector2(3.0, 5.5)
const WAITING_GAP := Vector2(1.5, 3.0)
const STRAFE_MIN_TICKS := 30
const STRAFE_MAX_TICKS := 75
const STRAFE_WEIGHT := 0.8
const WALL_MARGIN := 1.5
const HISTORY := 32

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
var _strafe := 1.0
var _strafe_ticks := 0

static var _curves := {}


func _init(ai_profile: AIProfile, stream: SimRandom) -> void:
	profile = ai_profile
	random = stream


func decide(battle: Battle, side: int) -> Dictionary:
	var me := battle.fighters[side]
	var foe := battle.fighters[1 - side]
	_remember(foe)
	_held += 1
	_since_decision += 1
	if not me.can_act():
		_intent = {}
		return {}
	var keep_moving: bool = _intent.get("use", -1) < 0 and _intent.get("dodge", Vector2.ZERO) == Vector2.ZERO
	if _since_decision < profile.decision_interval_ticks and keep_moving and not _intent.is_empty():
		return _movement_intent(me, _perceived(foe), _current)
	_since_decision = 0
	var seen := _perceived(foe)
	var threat := _threat(battle, me, seen, side)
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
		_:
			_intent = _movement_intent(me, seen, _current)
	return _intent


## Candidate actions with their considerations and scores, best first.
func _candidates(battle: Battle, me: Fighter, foe: Fighter, seen: Dictionary, threat: Dictionary) -> Array[Dictionary]:
	var gap := me.position.distance_to(seen.position) - me.radius - foe.radius
	# A threat only argues against committing to a move if the AI could dodge it instead.
	var can_avoid: bool = not threat.is_empty() and me.can_dodge() and _dodge_allowed.get(threat.key, false)
	var urgency := _urgency(threat.ticks) if can_avoid else 0.0
	var candidates: Array[Dictionary] = []
	var any_ready := false
	for i in me.moves.size():
		if not me.move_ready(i):
			continue
		any_ready = true
		var move := me.moves[i]
		var considerations := {
			"in_range": 1.0 if gap <= move.reach() else 0.0,
			"safe_to_commit": 1.0 - 0.6 * urgency,
		}
		if move.is_damaging():
			# Expected damage covers power, STAB, stats, stages and type at once; the stand-in's
			# move value still vetoes self-destructing early and discounts charge, recharge and
			# self-lowering moves.
			var expected := expected_damage(me, foe, move, battle.data())
			var adjusted := SimpleAI.move_score(me, foe, move) / maxf(move.power * move.expected_hits(), 1.0) if move.fixed_damage == 0 else 1.0
			considerations.damage = _sample("damage", expected * adjusted / maxf(foe.max_hp, 1.0))
			considerations.finisher = _sample("finisher", expected / maxf(foe.hp, 1.0))
		else:
			considerations.value = _sample("value", SimpleAI.move_score(me, foe, move) / VALUE_SCALE)
		candidates.append(_scored("move:" + move.id, Action.USE_MOVE, considerations, i))
	if can_avoid:
		candidates.append(_scored("dodge", Action.DODGE, {
			"urgency": urgency,
			"charges": _sample("charges", float(me.dodge_charges)),
			"danger": _sample("danger", threat.danger),
		}))
	var band := _band(me, gap)
	candidates.append(_scored("approach", Action.APPROACH, {"too_far": _sample("too_far", gap - band.y)}))
	candidates.append(_scored("retreat", Action.RETREAT, {"too_close": _sample("too_close", band.x - gap)}))
	candidates.append(_scored("circle", Action.CIRCLE, {"base": CIRCLE_SCORE + (0.0 if any_ready else WAITING_CIRCLE_BONUS)}))
	candidates.append(_scored("hold", Action.HOLD, {"base": HOLD_SCORE}))
	for candidate in candidates:
		if candidate.action == _current and candidate.score > 0.0 and candidate.kind >= Action.APPROACH:
			candidate.score += COMMITMENT_BONUS
	return candidates


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
	var moving := [Action.APPROACH, Action.RETREAT, Action.CIRCLE, Action.HOLD]
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


## Damage `move` would do on average (no crit, mean roll), for scoring.
static func expected_damage(attacker: Fighter, defender: Fighter, move: BattleMove, data: BattleData) -> float:
	if move.fixed_damage > 0:
		return move.fixed_damage * move.expected_hits()
	var attack := attacker.stat("atk" if move.physical else "spa")
	var defense := defender.stat("def" if move.physical else "spd")
	var base := floorf(floorf(floorf(2.0 * Rules.LEVEL / 5.0 + 2.0) * move.power * attack / defense) / 50.0) + 2.0
	var stab := Rules.STAB if move.type in attacker.types else 1.0
	var effectiveness := Rules.compressed_effectiveness(data.effectiveness(move.type, defender.types))
	return base * stab * effectiveness * (Rules.ROLL_MIN + Rules.ROLL_MAX) * 0.5 * move.expected_hits()


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
	if _history.size() < HISTORY:
		_history.append(snapshot)
	else:
		_history[_history_count % HISTORY] = snapshot
	_history_count += 1


## The opponent as this AI sees it: reaction_delay_ticks ago (or as early as remembered).
func _perceived(foe: Fighter) -> Dictionary:
	if _history_count == 0:
		_remember(foe)
	var index := maxi(_history_count - 1 - profile.reaction_delay_ticks, maxi(0, _history_count - HISTORY))
	return _history[index % HISTORY]


## The most urgent attack this AI has noticed: {"key", "direction", "ticks" (left until it
## lands), "danger" (share of our HP)} or {}. Each threat gets one dodge roll.
func _threat(battle: Battle, me: Fighter, seen: Dictionary, side: int) -> Dictionary:
	var foe := battle.fighters[1 - side]
	var data := battle.data()
	var best := {}
	var delay := profile.reaction_delay_ticks
	for projectile in battle.projectiles:
		if int(projectile.owner) == side or projectile.get("dodged", false):
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
		var move := foe.moves[projectile.move]
		var threat := {"key": "p%d" % int(projectile.id),
			"direction": velocity.normalized(), "ticks": t,
			"danger": expected_damage(foe, me, move, data) / maxf(me.hp, 1.0) if move.is_damaging() else 0.1}
		if best.is_empty() or threat.ticks < best.ticks:
			best = threat
	if seen.action == Fighter.Action.WINDUP:
		var move := foe.moves[seen.action_move]
		var reach := Rules.MELEE_DASH_RANGE if move.kind == BattleMove.Kind.MELEE else Rules.AREA_RADIUS
		var gap := me.position.distance_to(seen.position) - me.radius - foe.radius
		if (move.kind == BattleMove.Kind.MELEE or move.kind == BattleMove.Kind.AREA) and gap <= reach:
			var started := battle.tick - delay - (move.windup_ticks - int(seen.action_ticks))
			var threat := {"key": "w%d" % started, "direction": (me.position - seen.position).normalized(),
				"ticks": float(int(seen.action_ticks) - delay), "danger": expected_damage(foe, me, move, data) / maxf(me.hp, 1.0)}
			# A wind-up that has already landed by the time the AI sees it start is no threat.
			if threat.ticks >= 0.0 and (best.is_empty() or threat.ticks < best.ticks):
				best = threat
	if not best.is_empty() and not _judged.has(best.key):
		_judged[best.key] = true
		_dodge_allowed[best.key] = random.chance(profile.dodge_chance)
	return best


## The gap to keep, from the moves that are ready (close for melee and area, mid range for
## projectiles, a loose middle while waiting on cooldowns).
func _band(me: Fighter, _gap: float) -> Vector2:
	var melee := false
	var ranged := false
	for i in me.moves.size():
		if not me.move_ready(i) or not me.moves[i].is_damaging():
			continue
		if me.moves[i].kind == BattleMove.Kind.PROJECTILE:
			ranged = true
		else:
			melee = true
	if melee:
		return Vector2(0.0, Rules.MELEE_DASH_RANGE * 0.8)
	if ranged:
		return RANGED_GAP
	return WAITING_GAP


func _movement_intent(me: Fighter, seen: Dictionary, action: String) -> Dictionary:
	_strafe_ticks -= 1
	if _strafe_ticks <= 0:
		_strafe = 1.0 if random.chance(0.5) else -1.0
		_strafe_ticks = STRAFE_MIN_TICKS + int(random.next_u32() % (STRAFE_MAX_TICKS - STRAFE_MIN_TICKS + 1))
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
		_:
			return {"move": Vector2.ZERO}
	if me.position.length() > Rules.ARENA_RADIUS - me.radius - WALL_MARGIN:
		direction += -me.position.normalized()
		if side.dot(-me.position) < 0.0:
			_strafe = -_strafe
	return {"move": direction.normalized() if direction.length_squared() > 0.0 else Vector2.ZERO}


## Sideways to the threat: towards the centre near the wall, else a random side.
func _dodge_direction(me: Fighter, threat: Vector2) -> Vector2:
	var side := Vector2(-threat.y, threat.x)
	if me.position.length() > Rules.ARENA_RADIUS - WALL_MARGIN - Rules.DODGE_DISTANCE:
		return side if side.dot(-me.position) >= 0.0 else -side
	return side if random.chance(0.5) else -side
