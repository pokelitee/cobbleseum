class_name StandInAI
extends RefCounted
## Stand-in controller until the utility AI (concepts_brief.md §11, milestone 4):
## - dodges sideways when a projectile is about to hit or a melee strike is about to land,
##   deciding once per threat with DODGE_CHANCE;
## - uses the best-scoring ready move that's in range (move_score): damaging moves by power,
##   heals when hurt, buffs until +2, status on a foe without one, debuffs until -2;
## - otherwise keeps a range suited to its ready moves (close for melee, mid range for
##   ranged) and circles the opponent, switching direction now and then.
## Every choice draws from the side's own random stream.

## A projectile counts as a threat when it will reach us within this many ticks.
const THREAT_TICKS := 8
## A melee wind-up counts as a threat when it lands within this many ticks.
const MELEE_THREAT_TICKS := 4
const DODGE_CHANCE := 0.45
## Gap kept while ranged moves are ready, and while waiting on cooldowns.
const RANGED_GAP := Vector2(3.0, 5.5)
const WAITING_GAP := Vector2(1.5, 3.0)
const STRAFE_MIN_TICKS := 30
const STRAFE_MAX_TICKS := 75
const STRAFE_WEIGHT := 0.8
## Scores for non-damaging moves, on the same scale as move power.
const HEAL_SCORE := 140.0
const HEAL_BELOW := 0.6
const BUFF_SCORE := 85.0
const STATUS_SCORE := 95.0
const CONFUSE_SCORE := 70.0
const DEBUFF_SCORE := 55.0
const STAGE_TARGET := 2
## Damaging moves: charge and recharge moves are worth a little less, fixed damage a little
## more (it ignores defences), and self-destructing only when nearly knocked out.
const CHARGE_FACTOR := 0.75
const RECHARGE_FACTOR := 0.8
const FIXED_DAMAGE_FACTOR := 1.8
const SELF_DESTRUCT_BELOW := 0.25
## Within this distance of the wall, steer back toward the centre.
const WALL_MARGIN := 1.5

var random: SimRandom
## Threats already decided on, so each one gets a single dodge roll: projectiles by
## identity, melee wind-ups by the tick they started.
var _judged_projectiles: Array = []
var _judged_windup := -1
var _strafe := 1.0
var _strafe_ticks := 0


func _init(stream: SimRandom) -> void:
	random = stream


## One controller per side, each on its own random stream from the battle seed.
static func pair(seed: int) -> Array:
	return [
		StandInAI.new(SimRandom.stream(seed, Battle.Stream.SIDE_A)),
		StandInAI.new(SimRandom.stream(seed, Battle.Stream.SIDE_B)),
	]


func decide(battle: Battle, side: int) -> Dictionary:
	var me := battle.fighters[side]
	var foe := battle.fighters[1 - side]
	var intent := {"use": -1, "move": Vector2.ZERO, "dodge": Vector2.ZERO}
	if not me.can_act():
		return intent
	var threat := incoming_threat(battle, side)
	if not threat.is_empty() and me.can_dodge() and _first_look(battle, threat) and random.chance(DODGE_CHANCE):
		intent.dodge = _dodge_direction(me, threat.direction)
		return intent

	var gap := Battle._gap(me, foe)
	var best := -1
	var best_score := 0.0
	var ranged_ready := false
	var melee_ready := false
	for i in me.moves.size():
		if not me.move_ready(i):
			continue
		var move := me.moves[i]
		var score := move_score(me, foe, move)
		if score <= 0.0:
			continue
		if move.kind == BattleMove.Kind.MELEE or move.kind == BattleMove.Kind.AREA:
			melee_ready = true
		elif move.is_projectile():
			ranged_ready = true
		# Ties go to a random pick so the order of the moveset never decides.
		if gap <= move.reach() and battle.can_reach(me, foe, move) and (score > best_score or (score == best_score and random.chance(0.5))):
			best = i
			best_score = score
	if best >= 0:
		intent.use = best
		return intent

	var band := WAITING_GAP
	if melee_ready:
		band = Vector2(0.0, Rules.MELEE_DASH_RANGE * 0.8)
	elif ranged_ready:
		band = RANGED_GAP
	intent.move = battle.terrain.steer(me.position, me.radius, me.ground, me.climb, _steer(me, foe, gap, band))
	return intent


## How much the AI wants a move now; 0 means not at all.
static func move_score(me: Fighter, foe: Fighter, move: BattleMove) -> float:
	if move.is_damaging():
		return _damage_score(me, move)
	match move.kind:
		BattleMove.Kind.HEAL:
			var share := float(me.hp) / me.max_hp
			return HEAL_SCORE * (1.0 - share) if share < HEAL_BELOW else 0.0
		BattleMove.Kind.SELF_BUFF:
			for stat: String in move.boosts:
				if me.boosts[stat] < STAGE_TARGET:
					return BUFF_SCORE
			return 0.0
		BattleMove.Kind.DEBUFF:
			for stat: String in move.boosts:
				if foe.boosts[stat] > -STAGE_TARGET:
					return DEBUFF_SCORE
			return 0.0
		BattleMove.Kind.STATUS:
			if move.confuses:
				return CONFUSE_SCORE if foe.confusion_ticks == 0 else 0.0
			if not foe.status.is_empty():
				return 0.0
			for type: String in Rules.STATUS_IMMUNITIES.get(move.status, []):
				if type in foe.types:
					return 0.0
			return STATUS_SCORE
	return 0.0


static func _damage_score(me: Fighter, move: BattleMove) -> float:
	if move.self_destructs and float(me.hp) / me.max_hp > SELF_DESTRUCT_BELOW:
		return 0.0
	var score := move.power * move.expected_hits()
	if move.fixed_damage > 0:
		score = move.fixed_damage * FIXED_DAMAGE_FACTOR
	if move.charges:
		score *= CHARGE_FACTOR
	if move.recharges:
		score *= RECHARGE_FACTOR
	if move.fixed_damage == 0:
		# Weigh the attacking stat's current stage, and charge moves that lower it (Overheat,
		# Draco Meteor) for the drop too, so they aren't spammed down to -6.
		var stage: int = 0 if move.target_attacks else me.boosts[move.offensive_stat]
		score *= Rules.stage_multiplier(stage)
		var drop := move.own_stat_drop()
		if drop < 0:
			# Below -2 it waits for the stage to wear off rather than sinking it further.
			if stage + drop < -STAGE_TARGET:
				return 0.0
			score *= Rules.stage_multiplier(stage + drop) / Rules.stage_multiplier(stage)
	return score


## An attack about to hit `side`: {"direction": Vector2, "projectile": Dictionary} or
## {"direction", "windup_tick": int}; {} when there's none.
static func incoming_threat(battle: Battle, side: int) -> Dictionary:
	var me := battle.fighters[side]
	var foe := battle.fighters[1 - side]
	for projectile in battle.projectiles:
		if int(projectile.owner) == side or projectile.get("dodged", false):
			continue
		var velocity: Vector2 = projectile.velocity
		var start: Vector2 = projectile.position
		var end := start + velocity * THREAT_TICKS
		var closest := Geometry2D.get_closest_point_to_segment(me.position, start, end)
		if closest.distance_to(me.position) <= me.radius + Rules.PROJECTILE_RADIUS:
			return {"direction": velocity.normalized(), "projectile": projectile}
	if foe.action == Fighter.Action.WINDUP and foe.action_ticks <= MELEE_THREAT_TICKS:
		var move := foe.moves[foe.action_move]
		var reach := Rules.MELEE_DASH_RANGE if move.kind == BattleMove.Kind.MELEE else Rules.AREA_RADIUS
		if (move.kind == BattleMove.Kind.MELEE or move.kind == BattleMove.Kind.AREA) and Battle._gap(me, foe) <= reach:
			return {"direction": (me.position - foe.position).normalized(),
				"windup_tick": battle.tick - (move.windup_ticks - foe.action_ticks)}
	return {}


## True the first time a threat is seen; records it so it isn't rolled for again.
func _first_look(battle: Battle, threat: Dictionary) -> bool:
	if threat.has("windup_tick"):
		if threat.windup_tick == _judged_windup:
			return false
		_judged_windup = threat.windup_tick
		return true
	_judged_projectiles = _judged_projectiles.filter(func(p: Dictionary) -> bool:
		return battle.projectiles.any(func(q: Dictionary) -> bool: return is_same(p, q)))
	if _judged_projectiles.any(func(p: Dictionary) -> bool: return is_same(p, threat.projectile)):
		return false
	_judged_projectiles.append(threat.projectile)
	return true


## Sideways to the threat, toward the arena centre when near the wall, else a random side.
func _dodge_direction(me: Fighter, threat: Vector2) -> Vector2:
	var side := Vector2(-threat.y, threat.x)
	var inward := -me.position
	if me.position.length() > Rules.ARENA_RADIUS - WALL_MARGIN - Rules.DODGE_DISTANCE:
		return side if side.dot(inward) >= 0.0 else -side
	return side if random.chance(0.5) else -side


## Closes or opens the gap toward `band` (min, max) while circling the foe.
func _steer(me: Fighter, foe: Fighter, gap: float, band: Vector2) -> Vector2:
	_strafe_ticks -= 1
	if _strafe_ticks <= 0:
		_strafe = 1.0 if random.chance(0.5) else -1.0
		_strafe_ticks = STRAFE_MIN_TICKS + int(random.next_u32() % (STRAFE_MAX_TICKS - STRAFE_MIN_TICKS + 1))
	var toward := (foe.position - me.position).normalized()
	var radial := 0.0
	if gap > band.y:
		radial = 1.0
	elif gap < band.x:
		radial = -1.0
	var direction := toward * radial + Vector2(-toward.y, toward.x) * _strafe * STRAFE_WEIGHT
	if me.position.length() > Rules.ARENA_RADIUS - me.radius - WALL_MARGIN:
		direction += -me.position.normalized()
		_strafe = -_strafe if (Vector2(-toward.y, toward.x) * _strafe).dot(-me.position) < 0.0 else _strafe
	return direction.normalized() if direction.length_squared() > 0.0 else Vector2.ZERO
