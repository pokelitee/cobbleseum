class_name Battle
extends RefCounted
## The real-time battle simulation (concepts_brief.md §9, §10): plain objects, a fixed tick,
## simple geometric hit tests, seeded random streams and no engine physics. The same spec
## always produces the same battle on the same Godot build and platform.
##
## Each tick: controllers produce intents, then both sides act in an order that alternates
## every tick, projectiles move, and the battle checks for a knockout or the time cap.

enum Stream { BATTLE, SIDE_A, SIDE_B, COSMETIC }
enum Result { ONGOING, WIN_A, WIN_B, DRAW }

var tick := 0
var result := Result.ONGOING
var fighters: Array[Fighter] = []
var projectiles: Array[Dictionary] = []
## Events for presentation and highlight picking: {"tick", "type", "side", ...}.
var events: Array[Dictionary] = []
var spec: Dictionary
## With record_intents set (battles with a player), every tick's intents per side, as
## [move x, move y, use, dodge x, dodge y]; a ReplayController plays them back.
var record_intents := false
var intent_log: Array = [[], []]

var _data: BattleData
var _random: SimRandom
var _controllers: Array = []
var _hash := HashingContext.new()
var _checksum := ""
var _time_cap_ticks := 0
## Values hashed per fighter each tick, and the reused buffer they go in.
const FIGHTER_STATE_SIZE := 17
var _state := PackedFloat64Array()
## Projectiles fired so far; each gets the next number as a stable id.
var _projectile_count := 0


## `spec` = {"seed": int, "fighters": [{"species", "moves"?: [ids], "radius"?}, x2]}. Without
## "moves" a fighter gets its species' standard moveset (Movesets). The
## hitbox radius comes from the spec, else the roster, else Fighter.DEFAULT_RADIUS; with a
## roster loaded, species outside it are rejected.
## Controllers are objects with decide(battle, side) -> {"move": Vector2, "use": int,
## "dodge": Vector2 (zero for none)}; each
## owns its random stream (see random_stream()).
## Returns {"battle": Battle} or {"error": String}.
static func create(battle_spec: Dictionary, data: BattleData, controllers: Array) -> Dictionary:
	var entries: Array = battle_spec.get("fighters", [])
	if entries.size() != 2 or controllers.size() != 2:
		return {"error": "a battle needs exactly two fighters and two controllers"}
	var battle := Battle.new()
	battle.spec = battle_spec
	battle._data = data
	battle._controllers = controllers
	battle._random = SimRandom.stream(int(battle_spec.seed), Stream.BATTLE)
	battle._time_cap_ticks = Rules.seconds_to_ticks(Rules.TIME_CAP_SECONDS)
	for side in 2:
		var entry: Dictionary = entries[side]
		var species: Variant = data.species.get(entry.get("species", ""))
		if not species is Dictionary:
			return {"error": "unknown species '%s'" % entry.get("species", "")}
		if not data.roster.is_empty() and not data.roster.has(entry.species):
			return {"error": "'%s' is not in the roster (no Cobblemon model)" % entry.species}
		var radius := float(entry.get("radius", data.roster.get(entry.species, {}).get("radius", Fighter.DEFAULT_RADIUS)))
		var move_ids: Array = entry.get("moves", [])
		if move_ids.is_empty():
			var generated := data.standard_moveset(entry.species)
			if generated.has("error"):
				return generated
			move_ids = generated.moves
		var battle_moves: Array[BattleMove] = []
		for move_id: String in move_ids:
			var converted := data.convert_move(move_id)
			if converted.has("error"):
				return converted
			battle_moves.append(converted.move)
		if battle_moves.is_empty():
			return {"error": "%s has no moves" % entry.species}
		var fighter := Fighter.create(side, entry.species, species, battle_moves, radius)
		fighter.position = Vector2(0, (-0.5 if side == 0 else 0.5) * Rules.START_DISTANCE)
		fighter.facing = Vector2(0, 1 if side == 0 else -1)
		battle.fighters.append(fighter)
	battle._hash.start(HashingContext.HASH_SHA256)
	return {"battle": battle}


## An intent in the compact form intent_log stores.
static func intent_to_log(intent: Dictionary) -> Array:
	var move: Vector2 = intent.get("move", Vector2.ZERO)
	var dodge: Vector2 = intent.get("dodge", Vector2.ZERO)
	return [move.x, move.y, int(intent.get("use", -1)), dodge.x, dodge.y]


static func intent_from_log(entry: Array) -> Dictionary:
	var intent := {"move": Vector2(entry[0], entry[1])}
	if int(entry[2]) >= 0:
		intent.use = int(entry[2])
	if float(entry[3]) != 0.0 or float(entry[4]) != 0.0:
		intent.dodge = Vector2(entry[3], entry[4])
	return intent


## The species, moves and type chart the battle runs on.
func data() -> BattleData:
	return _data


func random_stream(stream: Stream) -> SimRandom:
	return SimRandom.stream(int(spec.seed), stream)


func is_over() -> bool:
	return result != Result.ONGOING


func step() -> void:
	if is_over():
		return
	var intents := []
	for side in 2:
		var intent: Dictionary = _controllers[side].decide(self, side)
		intents.append(intent)
		if record_intents:
			intent_log[side].append(intent_to_log(intent))
	var order := [0, 1] if tick % 2 == 0 else [1, 0]
	for side: int in order:
		_act(fighters[side], fighters[1 - side], intents[side])
	_move_projectiles()
	if tick == Rules.seconds_to_ticks(Rules.OVERTIME_SECONDS):
		_event("overtime", -1, {})
	_record_state()
	tick += 1
	_check_end()


## Runs until the battle ends. Returns the number of ticks simulated.
func run() -> int:
	while not is_over():
		step()
	return tick


## SHA-256 over every tick's state; equal checksums mean identical battles.
## Empty until the battle is over.
func checksum() -> String:
	if is_over() and _checksum.is_empty():
		_checksum = _hash.finish().hex_encode()
	return _checksum


func _act(fighter: Fighter, foe: Fighter, intent: Dictionary) -> void:
	if fighter.is_fainted():
		return
	for i in fighter.cooldowns.size():
		fighter.cooldowns[i] = maxi(0, fighter.cooldowns[i] - 1)
	if fighter.dodge_charges < Rules.DODGE_CHARGES:
		fighter.dodge_recharge_ticks += 1
		if fighter.dodge_recharge_ticks >= fighter.dodge_recharge_total:
			fighter.dodge_charges += 1
			fighter.dodge_recharge_ticks = 0
	_tick_conditions(fighter)
	if fighter.is_fainted() or fighter.is_incapacitated():
		fighter.followups.clear()
		return
	for followup in fighter.followups.duplicate():
		followup.ticks -= 1
		if followup.ticks <= 0:
			fighter.followups.erase(followup)
			_strike(fighter, foe, followup.move)
			if followup.last:
				_event("multi_hit_end", fighter.side, {"move": fighter.moves[followup.move].id})
	var to_foe := foe.position - fighter.position
	if to_foe.length_squared() > 0.0:
		fighter.facing = to_foe.normalized()
	match fighter.action:
		Fighter.Action.DODGE:
			_slide(fighter, foe, fighter.dodge_step)
			fighter.action_ticks -= 1
			if fighter.action_ticks <= 0:
				fighter.action = Fighter.Action.READY
		Fighter.Action.WINDUP:
			var move := fighter.moves[fighter.action_move]
			if move.kind == BattleMove.Kind.MELEE:
				# Melee moves dash in during the wind-up, stopping just inside reach.
				var gap := _gap(fighter, foe) - Rules.MELEE_REACH * 0.5
				if gap > 0.0:
					_slide(fighter, foe, fighter.facing * minf(gap, Rules.MELEE_DASH_SPEED / Rules.TICK_RATE))
			fighter.action_ticks -= 1
			if fighter.action_ticks <= 0:
				_release(fighter, foe)
		Fighter.Action.RECOVERY:
			fighter.action_ticks -= 1
			if fighter.action_ticks <= 0:
				fighter.action = Fighter.Action.READY
		_:
			var dodge: Vector2 = intent.get("dodge", Vector2.ZERO)
			var use: int = intent.get("use", -1)
			if dodge.length_squared() > 0.0 and fighter.can_dodge():
				fighter.dodge_charges -= 1
				fighter.action = Fighter.Action.DODGE
				fighter.action_ticks = Rules.seconds_to_ticks(Rules.DODGE_SECONDS)
				fighter.dodge_step = dodge.normalized() * Rules.DODGE_DISTANCE / fighter.action_ticks
				_event("dodge", fighter.side, {"direction": [dodge.normalized().x, dodge.normalized().y]})
			elif fighter.move_ready(use) and _gap(fighter, foe) <= fighter.moves[use].reach():
				var move := fighter.moves[use]
				if fighter.confusion_ticks > 0 and _random.chance(Rules.CONFUSION_CHANCE):
					_hurt_in_confusion(fighter)
					return
				fighter.action = Fighter.Action.WINDUP
				fighter.action_ticks = move.windup_ticks
				fighter.action_move = use
				fighter.cooldowns[use] = move.cooldown_ticks
				_event("windup", fighter.side, {"move": move.id})
			else:
				_walk(fighter, foe, intent.get("move", Vector2.ZERO))


## Gap between two fighters' hitboxes.
static func _gap(fighter: Fighter, foe: Fighter) -> float:
	return fighter.position.distance_to(foe.position) - fighter.radius - foe.radius


func _walk(fighter: Fighter, foe: Fighter, direction: Vector2) -> void:
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	_slide(fighter, foe, direction * (fighter.current_move_speed() / Rules.TICK_RATE))


## Moves a fighter by `delta`, kept inside the arena wall and outside the foe's hitbox
## (it slides around the foe instead of passing through).
func _slide(fighter: Fighter, foe: Fighter, delta: Vector2) -> void:
	var next := fighter.position + delta
	var contact := fighter.radius + foe.radius
	var away := next - foe.position
	if away.length() < contact:
		if away.length_squared() < 1e-8:
			away = fighter.position - foe.position
		next = foe.position + away.normalized() * contact
	var limit := Rules.ARENA_RADIUS - fighter.radius
	if next.length() > limit:
		next = next.normalized() * limit
	fighter.position = next


func _release(fighter: Fighter, foe: Fighter) -> void:
	var move := fighter.moves[fighter.action_move]
	fighter.action = Fighter.Action.RECOVERY
	fighter.action_ticks = move.recovery_ticks
	if move.is_self():
		if move.kind == BattleMove.Kind.HEAL:
			_heal(fighter, roundi(fighter.max_hp * move.heal_share), move.id)
		else:
			_boost(fighter, move.boosts, move.id)
	else:
		var hits := _roll_hits(move)
		_strike(fighter, foe, fighter.action_move)
		var interval := Rules.seconds_to_ticks(Rules.MULTI_HIT_INTERVAL)
		for i in range(1, hits):
			fighter.followups.append({"ticks": i * interval, "move": fighter.action_move, "last": i == hits - 1})
		if move.recharges:
			_event("recharge", fighter.side, {"move": move.id})
		if move.self_destructs:
			_hurt(fighter, fighter.hp, "self_destruct", {"move": move.id})


## One strike of a damaging move, or the launch of a projectile.
func _strike(fighter: Fighter, foe: Fighter, move_index: int) -> void:
	var move := fighter.moves[move_index]
	match move.kind:
		BattleMove.Kind.MELEE, BattleMove.Kind.AREA:
			var reach := Rules.MELEE_REACH if move.kind == BattleMove.Kind.MELEE else Rules.AREA_RADIUS
			if move.kind == BattleMove.Kind.AREA:
				_event("blast", fighter.side, {"move": move.id})
			if _gap(fighter, foe) > reach or foe.is_fainted():
				_event("miss", fighter.side, {"move": move.id})
			elif foe.is_invulnerable():
				_event("miss", fighter.side, {"move": move.id})
				_event("dodged", foe.side, {"move": move.id})
			else:
				_hit(fighter, foe, move)
		_:
			_projectile_count += 1
			projectiles.append({
				"id": _projectile_count,
				"owner": fighter.side,
				"move": move_index,
				"position": fighter.position + fighter.facing * fighter.radius,
				"velocity": fighter.facing * (move.projectile_speed / Rules.TICK_RATE),
				"travelled": 0.0,
			})
			_event("fire", fighter.side, {"move": move.id})


## Hits for one use: fixed, or 2-5 with the main-series weights.
func _roll_hits(move: BattleMove) -> int:
	if move.hits_min == move.hits_max:
		return move.hits_min
	var roll := _random.next_float()
	var total := 0.0
	for i in Rules.MULTI_HIT_WEIGHTS.size():
		total += Rules.MULTI_HIT_WEIGHTS[i]
		if roll < total:
			return mini(move.hits_min + i, move.hits_max)
	return move.hits_max


func _move_projectiles() -> void:
	var remaining: Array[Dictionary] = []
	for projectile in projectiles:
		var owner := fighters[projectile.owner]
		var target := fighters[1 - projectile.owner]
		var start: Vector2 = projectile.position
		var end: Vector2 = start + projectile.velocity
		var closest := Geometry2D.get_closest_point_to_segment(target.position, start, end)
		var move := owner.moves[projectile.move]
		if closest.distance_to(target.position) <= target.radius + Rules.PROJECTILE_RADIUS and not target.is_fainted():
			if not target.is_invulnerable():
				if move.is_damaging():
					_hit(owner, target, move)
				else:
					_land(owner, target, move)
				continue
			if not projectile.get("dodged", false):
				projectile.dodged = true  # it flies on through the dodging fighter
				_event("dodged", target.side, {"move": move.id})
		projectile.position = end
		projectile.travelled += (projectile.velocity as Vector2).length()
		if projectile.travelled < Rules.PROJECTILE_RANGE * 1.5 and end.length() < Rules.ARENA_RADIUS:
			remaining.append(projectile)
		else:
			_event("miss", owner.side, {"move": move.id})
	projectiles = remaining


func _hit(attacker: Fighter, defender: Fighter, move: BattleMove) -> void:
	var outcome := damage(attacker, defender, move, _data, _random)
	outcome.damage = maxi(1, floori(outcome.damage * Rules.overtime_factor(tick)))
	var dealt := mini(outcome.damage, defender.hp)
	defender.hp -= dealt
	_event("hit", attacker.side, {"move": move.id, "damage": outcome.damage, "crit": outcome.crit,
		"effectiveness": outcome.effectiveness, "hp": defender.hp})
	if defender.is_fainted():
		_event("faint", defender.side, {})
	else:
		if defender.status == "slp" or (defender.status == "frz" and move.type == "Fire"):
			_end_status(defender)
		for effect in move.secondaries:
			if _random.chance(effect.chance / 100.0):
				_apply_effect(attacker, defender, effect, move.id)
	if move.drain_share > 0.0 and not attacker.is_fainted():
		_heal(attacker, maxi(1, roundi(dealt * move.drain_share)), move.id)
	if move.recoil_share > 0.0:
		var recoil := maxi(1, roundi(dealt * move.recoil_share))
		_hurt(attacker, recoil, "recoil", {"move": move.id})
	if not move.self_boosts.is_empty() and not attacker.is_fainted():
		_boost(attacker, move.self_boosts, move.id)


## A debuff or status projectile reaching its target.
func _land(attacker: Fighter, defender: Fighter, move: BattleMove) -> void:
	_event("landed", attacker.side, {"move": move.id})
	_apply_effect(attacker, defender, {"boosts": move.boosts, "status": move.status, "confuses": move.confuses}, move.id)


func _apply_effect(attacker: Fighter, defender: Fighter, effect: Dictionary, move_id: String) -> void:
	if not str(effect.get("status", "")).is_empty():
		_inflict(defender, effect.status)
	if effect.get("confuses", false) and defender.confusion_ticks == 0:
		defender.confusion_ticks = Rules.seconds_to_ticks(Rules.CONFUSION_SECONDS)
		_event("status", defender.side, {"status": "confusion"})
	if not effect.get("boosts", {}).is_empty():
		_boost(defender, effect.boosts, move_id)
	if not effect.get("self_boosts", {}).is_empty():
		_boost(attacker, effect.self_boosts, move_id)


## Gives a major status unless the fighter already has one or its type is immune.
func _inflict(fighter: Fighter, status: String) -> void:
	if not fighter.status.is_empty() or fighter.is_fainted():
		return
	for type: String in Rules.STATUS_IMMUNITIES.get(status, []):
		if type in fighter.types:
			return
	fighter.status = status
	fighter.toxic_level = 0
	if status == "slp" or status == "frz":
		fighter.followups.clear()
	match status:
		"slp":
			fighter.status_ticks = Rules.seconds_to_ticks(_random.range_float(Rules.SLEEP_MIN_SECONDS, Rules.SLEEP_MAX_SECONDS))
		"frz":
			fighter.status_ticks = Rules.seconds_to_ticks(Rules.FREEZE_SECONDS)
		_:
			fighter.status_ticks = Rules.seconds_to_ticks(Rules.STATUS_SECONDS)
	_event("status", fighter.side, {"status": status})


func _end_status(fighter: Fighter) -> void:
	_event("status_end", fighter.side, {"status": fighter.status})
	fighter.status = ""
	fighter.status_ticks = 0


## Changes stat stages within +-6 and reports the changes that took effect.
func _boost(fighter: Fighter, changes: Dictionary, move_id: String) -> void:
	var applied := {}
	for stat: String in changes:
		var before: int = fighter.boosts[stat]
		fighter.boosts[stat] = clampi(before + int(changes[stat]), -Rules.MAX_STAGE, Rules.MAX_STAGE)
		if fighter.boosts[stat] != before:
			applied[stat] = fighter.boosts[stat] - before
	if not applied.is_empty():
		fighter.stage_ticks = 0
		_event("boost", fighter.side, {"boosts": applied, "move": move_id})


## Moves every stat stage one step toward 0 once they've gone unchanged long enough.
func _decay_stages(fighter: Fighter) -> void:
	fighter.stage_ticks += 1
	if fighter.stage_ticks < Rules.seconds_to_ticks(Rules.STAGE_DECAY_SECONDS):
		return
	fighter.stage_ticks = 0
	var applied := {}
	for stat: String in fighter.boosts:
		var stage: int = fighter.boosts[stat]
		if stage != 0:
			fighter.boosts[stat] = stage - signi(stage)
			applied[stat] = -signi(stage)
	if not applied.is_empty():
		_event("stage_decay", fighter.side, {"boosts": applied})


func _heal(fighter: Fighter, amount: int, move_id: String) -> void:
	var healed := mini(amount, fighter.max_hp - fighter.hp)
	if healed > 0:
		fighter.hp += healed
		_event("heal", fighter.side, {"amount": healed, "hp": fighter.hp, "move": move_id})


## Takes HP outside a hit (status damage, recoil, confusion), reporting it as `type`.
func _hurt(fighter: Fighter, amount: int, type: String, details: Dictionary) -> void:
	if fighter.is_fainted():
		return
	fighter.hp = maxi(0, fighter.hp - amount)
	details.merge({"damage": amount, "hp": fighter.hp})
	_event(type, fighter.side, details)
	if fighter.is_fainted():
		_event("faint", fighter.side, {})


## Status timers, damage over time and paralysis stuns, once per tick before acting.
func _tick_conditions(fighter: Fighter) -> void:
	_decay_stages(fighter)
	if fighter.stun_ticks > 0:
		fighter.stun_ticks -= 1
	if fighter.confusion_ticks > 0:
		fighter.confusion_ticks -= 1
		if fighter.confusion_ticks == 0:
			_event("status_end", fighter.side, {"status": "confusion"})
	if fighter.status.is_empty():
		return
	fighter.status_ticks -= 1
	if fighter.status_ticks % Rules.TICK_RATE == 0:
		match fighter.status:
			"brn":
				_hurt(fighter, maxi(1, roundi(fighter.max_hp * Rules.BURN_DAMAGE)), "status_damage", {"status": "brn"})
			"psn":
				_hurt(fighter, maxi(1, roundi(fighter.max_hp * Rules.POISON_DAMAGE)), "status_damage", {"status": "psn"})
			"tox":
				fighter.toxic_level += 1
				_hurt(fighter, maxi(1, roundi(fighter.max_hp * Rules.TOXIC_STEP * fighter.toxic_level)), "status_damage", {"status": "tox"})
			"par":
				if _random.chance(Rules.PARALYSIS_STUN_CHANCE):
					fighter.stun_ticks = Rules.seconds_to_ticks(Rules.PARALYSIS_STUN_SECONDS)
					_event("stunned", fighter.side, {})
	if fighter.status_ticks <= 0 and not fighter.is_fainted():
		_end_status(fighter)


## A confused fighter sometimes hits itself instead of using its move (§9.5).
func _hurt_in_confusion(fighter: Fighter) -> void:
	var attack := fighter.stat("atk")
	var defense := fighter.stat("def")
	var base := floorf(floorf(floorf(2.0 * Rules.LEVEL / 5.0 + 2.0) * Rules.CONFUSION_POWER * attack / defense) / 50.0) + 2.0
	_hurt(fighter, maxi(1, floori(base * _random.range_float(Rules.ROLL_MIN, Rules.ROLL_MAX))), "confusion_hit", {})
	fighter.action = Fighter.Action.RECOVERY
	fighter.action_ticks = Rules.seconds_to_ticks(Rules.CONFUSION_RECOVERY)


## Main-series damage formula with Cobbleseum's compressed type multipliers (§9.4), using
## stats after stat stages and burn. Fixed-damage moves ignore stats, type and crits.
static func damage(attacker: Fighter, defender: Fighter, move: BattleMove, data: BattleData, random: SimRandom) -> Dictionary:
	if move.fixed_damage > 0:
		return {"damage": move.fixed_damage, "crit": false, "effectiveness": 1.0}
	var attack := attacker.stat("atk" if move.physical else "spa")
	var defense := defender.stat("def" if move.physical else "spd")
	var base := floorf(floorf(floorf(2.0 * Rules.LEVEL / 5.0 + 2.0) * move.power * attack / defense) / 50.0) + 2.0
	var stab := Rules.STAB if move.type in attacker.types else 1.0
	var effectiveness := Rules.compressed_effectiveness(data.effectiveness(move.type, defender.types))
	var crit := random.chance(Rules.CRIT_CHANCE)
	var roll := random.range_float(Rules.ROLL_MIN, Rules.ROLL_MAX)
	var total := base * stab * effectiveness * (Rules.CRIT_MULTIPLIER if crit else 1.0) * roll
	return {"damage": maxi(1, floori(total)), "crit": crit, "effectiveness": effectiveness}


func _check_end() -> void:
	var a_down := fighters[0].is_fainted()
	var b_down := fighters[1].is_fainted()
	if a_down and b_down:
		result = Result.DRAW
	elif b_down:
		result = Result.WIN_A
	elif a_down:
		result = Result.WIN_B
	elif tick >= _time_cap_ticks:
		result = Result.DRAW
		_event("time_up", -1, {})


## Hashes every value that defines the state. Runs every tick, so it fills a reused array.
func _record_state() -> void:
	_state.resize(FIGHTER_STATE_SIZE * 2 + projectiles.size() * 2)
	var i := 0
	for fighter in fighters:
		_state[i] = fighter.position.x
		_state[i + 1] = fighter.position.y
		_state[i + 2] = fighter.hp
		_state[i + 3] = fighter.action
		_state[i + 4] = fighter.action_ticks
		_state[i + 5] = fighter.dodge_charges
		_state[i + 6] = fighter.status_ticks
		_state[i + 7] = fighter.confusion_ticks
		_state[i + 8] = fighter.stun_ticks
		_state[i + 9] = fighter.followups.size()
		_state[i + 10] = Fighter.STATUS_CODES.find(fighter.status)
		_state[i + 11] = fighter.boosts.atk
		_state[i + 12] = fighter.boosts.def
		_state[i + 13] = fighter.boosts.spa
		_state[i + 14] = fighter.boosts.spd
		_state[i + 15] = fighter.boosts.spe
		_state[i + 16] = fighter.stage_ticks
		i += FIGHTER_STATE_SIZE
	for projectile in projectiles:
		_state[i] = projectile.position.x
		_state[i + 1] = projectile.position.y
		i += 2
	_hash.update(_state.to_byte_array())


func _event(type: String, side: int, details: Dictionary) -> void:
	var event := {"tick": tick, "type": type, "side": side}
	event.merge(details)
	events.append(event)
