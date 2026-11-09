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

var _data: BattleData
var _random: SimRandom
var _controllers: Array = []
var _hash := HashingContext.new()
var _checksum := ""
var _time_cap_ticks := 0


## `spec` = {"seed": int, "fighters": [{"species", "moves": [ids], "radius"?}, x2]}.
## Controllers are objects with decide(battle, side) -> {"move": Vector2, "use": int}; each
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
		var battle_moves: Array[BattleMove] = []
		for move_id: String in entry.get("moves", []):
			if not data.moves.has(move_id):
				return {"error": "unknown move '%s'" % move_id}
			var converted := BattleMove.from_showdown(move_id, data.moves[move_id])
			if converted.has("error"):
				return converted
			battle_moves.append(converted.move)
		if battle_moves.is_empty():
			return {"error": "%s has no moves" % entry.species}
		var fighter := Fighter.create(side, entry.species, species, battle_moves, float(entry.get("radius", Fighter.DEFAULT_RADIUS)))
		fighter.position = Vector2(0, (-0.5 if side == 0 else 0.5) * Rules.START_DISTANCE)
		fighter.facing = Vector2(0, 1 if side == 0 else -1)
		battle.fighters.append(fighter)
	battle._hash.start(HashingContext.HASH_SHA256)
	return {"battle": battle}


func random_stream(stream: Stream) -> SimRandom:
	return SimRandom.stream(int(spec.seed), stream)


func is_over() -> bool:
	return result != Result.ONGOING


func step() -> void:
	if is_over():
		return
	var intents := []
	for side in 2:
		intents.append(_controllers[side].decide(self, side))
	var order := [0, 1] if tick % 2 == 0 else [1, 0]
	for side: int in order:
		_act(fighters[side], fighters[1 - side], intents[side])
	_move_projectiles()
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
	var to_foe := foe.position - fighter.position
	if to_foe.length_squared() > 0.0:
		fighter.facing = to_foe.normalized()
	match fighter.action:
		Fighter.Action.WINDUP:
			fighter.action_ticks -= 1
			if fighter.action_ticks <= 0:
				_release(fighter, foe)
		Fighter.Action.RECOVERY:
			fighter.action_ticks -= 1
			if fighter.action_ticks <= 0:
				fighter.action = Fighter.Action.READY
		_:
			var use: int = intent.get("use", -1)
			if fighter.move_ready(use):
				var move := fighter.moves[use]
				fighter.action = Fighter.Action.WINDUP
				fighter.action_ticks = move.windup_ticks
				fighter.action_move = use
				fighter.cooldowns[use] = move.cooldown_ticks
				_event("windup", fighter.side, {"move": move.id})
			else:
				_walk(fighter, foe, intent.get("move", Vector2.ZERO))


func _walk(fighter: Fighter, foe: Fighter, direction: Vector2) -> void:
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	var next := fighter.position + direction * (fighter.move_speed / Rules.TICK_RATE)
	var limit := Rules.ARENA_RADIUS - fighter.radius
	if next.length() > limit:
		next = next.normalized() * limit
	var gap := fighter.radius + foe.radius
	if next.distance_to(foe.position) < gap:
		return  # fighters don't walk through each other
	fighter.position = next


func _release(fighter: Fighter, foe: Fighter) -> void:
	var move := fighter.moves[fighter.action_move]
	fighter.action = Fighter.Action.RECOVERY
	fighter.action_ticks = move.recovery_ticks
	if move.kind == BattleMove.Kind.MELEE:
		var gap := fighter.position.distance_to(foe.position) - fighter.radius - foe.radius
		if gap <= Rules.MELEE_REACH:
			_hit(fighter, foe, move)
		else:
			_event("miss", fighter.side, {"move": move.id})
	else:
		projectiles.append({
			"owner": fighter.side,
			"move": fighter.action_move,
			"position": fighter.position + fighter.facing * fighter.radius,
			"velocity": fighter.facing * (move.projectile_speed / Rules.TICK_RATE),
			"travelled": 0.0,
		})
		_event("fire", fighter.side, {"move": move.id})


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
			_hit(owner, target, move)
			continue
		projectile.position = end
		projectile.travelled += (projectile.velocity as Vector2).length()
		if projectile.travelled < Rules.PROJECTILE_RANGE * 1.5 and end.length() < Rules.ARENA_RADIUS:
			remaining.append(projectile)
		else:
			_event("miss", owner.side, {"move": move.id})
	projectiles = remaining


func _hit(attacker: Fighter, defender: Fighter, move: BattleMove) -> void:
	var outcome := damage(attacker, defender, move, _data, _random)
	defender.hp = maxi(0, defender.hp - outcome.damage)
	_event("hit", attacker.side, {"move": move.id, "damage": outcome.damage, "crit": outcome.crit,
		"effectiveness": outcome.effectiveness, "hp": defender.hp})
	if defender.is_fainted():
		_event("faint", defender.side, {})


## Main-series damage formula with Cobbleseum's compressed type multipliers (§9.4).
static func damage(attacker: Fighter, defender: Fighter, move: BattleMove, data: BattleData, random: SimRandom) -> Dictionary:
	var attack: int = attacker.stats.atk if move.physical else attacker.stats.spa
	var defense: int = defender.stats.def if move.physical else defender.stats.spd
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


func _record_state() -> void:
	var state := PackedFloat64Array()
	for fighter in fighters:
		state.append_array([fighter.position.x, fighter.position.y, fighter.hp, fighter.action, fighter.action_ticks])
	for projectile in projectiles:
		state.append_array([projectile.position.x, projectile.position.y])
	_hash.update(state.to_byte_array())


func _event(type: String, side: int, details: Dictionary) -> void:
	var event := {"tick": tick, "type": type, "side": side}
	event.merge(details)
	events.append(event)
