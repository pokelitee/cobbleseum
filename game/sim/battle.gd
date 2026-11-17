class_name Battle
extends RefCounted
## The real-time battle simulation (concepts_brief.md §9, §10): plain objects, a fixed tick,
## simple geometric hit tests, seeded random streams and no engine physics. The same spec
## always produces the same battle on the same Godot build and platform.
##
## Each tick: controllers produce intents, then both sides act in an order that alternates
## every tick, projectiles move, and the battle checks for a knockout or the time cap.

enum Stream { BATTLE, SIDE_A, SIDE_B, COSMETIC, TERRAIN }
enum Result { ONGOING, WIN_A, WIN_B, DRAW }

var tick := 0
var result := Result.ONGOING
var fighters: Array[Fighter] = []
var projectiles: Array[Dictionary] = []
## Events for presentation and highlight picking: {"tick", "type", "side", ...}.
var events: Array[Dictionary] = []
var spec: Dictionary
## The arena preset (Arenas), from the spec's "arena" or else the fighters' types and the seed.
var arena := ""
## The arena's ground (§9.8), from its field and the seed.
var terrain: Terrain
## The arena conditions (§9.11): the weather, shared with both fighters.
var conditions := ArenaConditions.new()
## With record_intents set (battles with a player), every tick's intents per side, as
## [move x, move y, use, dodge x, dodge y, feint, guard]; a ReplayController plays them back.
var record_intents := false
var intent_log: Array = [[], []]

var _data: BattleData
var _random: SimRandom
var _controllers: Array = []
var _hash := HashingContext.new()
var _checksum := ""
var _time_cap_ticks := 0
## Values hashed per fighter each tick, and the reused buffer they go in.
const FIGHTER_STATE_SIZE := 32
var _state := PackedFloat64Array()
## Projectiles fired so far; each gets the next number as a stable id.
var _projectile_count := 0


## `spec` = {"seed": int, "fighters": [{"species", "moves"?: [ids], "radius"?}, x2],
## "arena"?: preset, "weather"?: a starting weather ("" for none, else the preset's),
## "rules_version"?: int, "data_versions"?: {source: SHA-256}}. Without
## "moves" a fighter gets its species' standard moveset (Movesets). The
## hitbox radius comes from the spec, else the roster, else Fighter.DEFAULT_RADIUS; with a
## roster loaded, species outside it are rejected. A spec that names a rules or data version
## other than these is rejected, since it would play as a different battle.
## Controllers are objects with decide(battle, side) -> {"move": Vector2, "use": int,
## "dodge": Vector2 (zero for none), "feint": int (a move to feint), "guard": bool}; each
## owns its random stream (see random_stream()).
## Returns {"battle": Battle} or {"error": String}.
static func create(battle_spec: Dictionary, data: BattleData, controllers: Array) -> Dictionary:
	var version_problem := _version_problem(battle_spec, data)
	if not version_problem.is_empty():
		return {"error": version_problem}
	var entries: Array = battle_spec.get("fighters", [])
	if entries.size() != 2 or controllers.size() != 2:
		return {"error": "a battle needs exactly two fighters and two controllers"}
	var battle := Battle.new()
	battle.spec = battle_spec
	battle._data = data
	battle._controllers = controllers
	battle._random = SimRandom.stream(int(battle_spec.seed), Stream.BATTLE)
	battle._time_cap_ticks = Rules.seconds_to_ticks(Rules.TIME_CAP_SECONDS)
	var types: Array = []
	for entry: Dictionary in entries:
		types.append_array(data.species.get(entry.get("species", ""), {}).get("types", []))
	battle.arena = Arenas.choose(str(battle_spec.get("arena", "")), types, int(battle_spec.seed))
	battle.terrain = Terrain.generate(Arenas.preset(battle.arena).field, SimRandom.stream(int(battle_spec.seed), Stream.TERRAIN),
		Arenas.enclosed(battle.arena))
	var weather := str(battle_spec.get("weather", Arenas.preset(battle.arena).get("weather", "")))
	if not weather.is_empty() and not weather in ArenaConditions.WEATHERS:
		return {"error": "unknown weather '%s' (one of %s)" % [weather, ArenaConditions.WEATHERS]}
	if not weather.is_empty():
		battle.conditions.set_weather(weather, -1)
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
		var ability := str(entry.get("ability", data.standard_ability(entry.species)))
		if not ability.is_empty() and not Abilities.is_known(ability):
			return {"error": "ability '%s' isn't supported (see %s)" % [ability, Abilities.TABLE_FILE]}
		fighter.set_ability(ability)
		var item := str(entry.get("item", Items.standard(species, battle_moves, data, data.standard_ability(entry.species))))
		if not item.is_empty() and not Items.is_known(item):
			return {"error": "item '%s' isn't supported (see %s)" % [item, Items.TABLE_FILE]}
		fighter.set_item(item)
		fighter.can_evolve = Items.can_evolve(species, data)
		fighter.arena = battle.conditions
		fighter.position = Vector2(0, (-0.5 if side == 0 else 0.5) * Rules.START_DISTANCE)
		fighter.facing = Vector2(0, 1 if side == 0 else -1)
		fighter.ground = battle.terrain.height_at(fighter.position)
		battle.fighters.append(fighter)
	battle._hash.start(HashingContext.HASH_SHA256)
	return {"battle": battle}


static func _version_problem(battle_spec: Dictionary, data: BattleData) -> String:
	if battle_spec.has("rules_version") and int(battle_spec.rules_version) != Rules.RULES_VERSION:
		return ("the battle spec is for rules version %d, not the current %d, so it would replay as a different battle;" +
			" replay it from a commit with rules version %d") % [int(battle_spec.rules_version), Rules.RULES_VERSION, int(battle_spec.rules_version)]
	var named: Variant = battle_spec.get("data_versions", {})
	if not named is Dictionary:
		return "the battle spec's data_versions must be an object of source: SHA-256"
	for source: String in named:
		var loaded: String = data.versions.get(source, "")
		if str(named[source]) != loaded:
			return ("the battle spec is for %s data %s, not the loaded %s, so it would replay as a different battle;" +
				" replay it from a commit whose sources.json pins that data") % [source, str(named[source]).left(12),
				loaded.left(12) if not loaded.is_empty() else "(unversioned)"]
	return ""


## The battle spec to save after a battle with record_intents: the rules and data versions it
## ran under, every tick's intents per side in place of the AI, and the checksum. It replays
## exactly, and create() rejects it under other versions.
func saved_spec() -> Dictionary:
	var saved := {"rules_version": Rules.RULES_VERSION, "data_versions": _data.versions.duplicate()}
	saved.merge(spec.duplicate(true))
	for side in 2:
		saved.fighters[side].erase("ai")
		saved.fighters[side].intents = intent_log[side]
	saved.checksum = checksum()
	return saved


## An intent in the compact form intent_log stores.
static func intent_to_log(intent: Dictionary) -> Array:
	var move: Vector2 = intent.get("move", Vector2.ZERO)
	var dodge: Vector2 = intent.get("dodge", Vector2.ZERO)
	return [move.x, move.y, int(intent.get("use", -1)), dodge.x, dodge.y, int(intent.get("feint", -1)),
		1 if intent.get("guard", false) else 0]


static func intent_from_log(entry: Array) -> Dictionary:
	var intent := {"move": Vector2(entry[0], entry[1])}
	if int(entry[2]) >= 0:
		intent.use = int(entry[2])
	if float(entry[3]) != 0.0 or float(entry[4]) != 0.0:
		intent.dodge = Vector2(entry[3], entry[4])
	if entry.size() > 5 and int(entry[5]) >= 0:
		intent.feint = int(entry[5])
	if entry.size() > 6 and int(entry[6]) != 0:
		intent.guard = true
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
	if tick == 0:
		_start_conditions()
	var order := [0, 1] if tick % 2 == 0 else [1, 0]
	for side: int in order:
		_act(fighters[side], fighters[1 - side], intents[side])
	_move_projectiles()
	var ended := conditions.tick()
	if not ended.is_empty():
		_event("weather_end", -1, {"weather": ended})
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
	if fighter.is_knocked_out():
		return
	for i in fighter.cooldowns.size():
		fighter.cooldowns[i] = maxi(0, fighter.cooldowns[i] - 1)
	fighter.feint_cooldown = maxi(0, fighter.feint_cooldown - 1)
	fighter.guard_cooldown = maxi(0, fighter.guard_cooldown - 1)
	if fighter.dodge_charges < Rules.DODGE_CHARGES:
		fighter.dodge_recharge_ticks += 1
		if fighter.dodge_recharge_ticks >= fighter.dodge_recharge_total:
			fighter.dodge_charges += 1
			fighter.dodge_recharge_ticks = 0
	_tick_conditions(fighter)
	_tick_abilities(fighter, foe)
	_tick_item(fighter)
	_tick_weather(fighter)
	if fighter.is_knocked_out() or fighter.is_incapacitated():
		fighter.followups.clear()
		if not fighter.is_knocked_out():
			_drift(fighter, foe, Vector2.ZERO)
		return
	for followup in fighter.followups.duplicate():
		if not fighter.followups.has(followup):
			continue  # a parry dropped it
		followup.ticks -= 1
		if followup.ticks <= 0:
			fighter.followups.erase(followup)
			_strike(fighter, foe, followup.move)
			if followup.last:
				_event("multi_hit_end", fighter.side, {"move": fighter.moves[followup.move].id})
	var to_foe := (foe.position - fighter.position).normalized()
	match fighter.action:
		Fighter.Action.DODGE:
			_slide(fighter, foe, fighter.dodge_step)
			fighter.velocity = fighter.dodge_step * Rules.TICK_RATE
			fighter.action_ticks -= 1
			if fighter.action_ticks <= 0:
				fighter.action = Fighter.Action.READY
		Fighter.Action.WINDUP:
			_turn(fighter, to_foe, Rules.AIM_TURN_RATE)
			var move := fighter.moves[fighter.action_move]
			var gap := _gap(fighter, foe) - Rules.MELEE_REACH * 0.5
			if move.kind == BattleMove.Kind.MELEE and gap > 0.0:
				# Melee moves dash in during the wind-up, stopping just inside reach.
				fighter.velocity = Vector2.ZERO
				_slide(fighter, foe, to_foe * minf(gap, Rules.MELEE_DASH_SPEED / Rules.TICK_RATE))
			else:
				_drift(fighter, foe, Vector2.ZERO)
			fighter.action_ticks -= 1
			if fighter.feinting and fighter.action_ticks <= Rules.FEINT_BREAK_TICKS:
				fighter.feinting = false
				fighter.action = Fighter.Action.READY
				_event("feint_end", fighter.side, {"move": move.id})
			elif fighter.action_ticks <= 0:
				_release(fighter, foe)
		Fighter.Action.GUARD:
			_turn(fighter, to_foe, Rules.AIM_TURN_RATE)
			_drift(fighter, foe, Vector2.ZERO)
			fighter.action_ticks -= 1
			if fighter.action_ticks == Rules.seconds_to_ticks(Rules.GUARD_RECOVERY):
				_event("guard_end", fighter.side, {"blocked": fighter.guard_blocked})
				if fighter.guard_blocked:
					fighter.action_ticks = 0
			if fighter.action_ticks <= 0:
				fighter.action = Fighter.Action.READY
		Fighter.Action.RECOVERY:
			_turn(fighter, to_foe, Rules.TURN_RATE)
			_drift(fighter, foe, Vector2.ZERO)
			fighter.action_ticks -= 1
			if fighter.action_ticks <= 0:
				fighter.action = Fighter.Action.READY
		_:
			var dodge: Vector2 = intent.get("dodge", Vector2.ZERO)
			var use: int = intent.get("use", -1)
			var feint: int = intent.get("feint", -1)
			var guard: bool = intent.get("guard", false)
			if dodge.length_squared() > 0.0 and fighter.can_dodge():
				fighter.dodge_charges -= 1
				fighter.action = Fighter.Action.DODGE
				fighter.action_ticks = Rules.seconds_to_ticks(Rules.DODGE_SECONDS)
				fighter.dodge_step = dodge.normalized() * Rules.DODGE_DISTANCE / fighter.action_ticks
				_event("dodge", fighter.side, {"direction": [dodge.normalized().x, dodge.normalized().y]})
			elif guard and fighter.can_guard():
				fighter.action = Fighter.Action.GUARD
				fighter.action_ticks = Rules.seconds_to_ticks(Rules.GUARD_SECONDS) + Rules.seconds_to_ticks(Rules.GUARD_RECOVERY)
				fighter.guard_cooldown = Rules.seconds_to_ticks(Rules.GUARD_COOLDOWN)
				fighter.guard_blocked = false
				_event("guard", fighter.side, {})
			elif fighter.move_ready(use) and _gap(fighter, foe) <= fighter.moves[use].reach():
				var move := fighter.moves[use]
				if fighter.confusion_ticks > 0 and _random.chance(Rules.CONFUSION_CHANCE):
					_hurt_in_confusion(fighter)
					return
				fighter.action = Fighter.Action.WINDUP
				fighter.action_ticks = fighter.windup_ticks(move)
				fighter.action_move = use
				fighter.cooldowns[use] = move.cooldown_ticks
				_event("windup", fighter.side, {"move": move.id})
			elif fighter.can_feint(feint) and _gap(fighter, foe) <= fighter.moves[feint].reach():
				var move := fighter.moves[feint]
				fighter.action = Fighter.Action.WINDUP
				fighter.action_ticks = move.windup_ticks
				fighter.action_move = feint
				fighter.feinting = true
				fighter.feint_cooldown = Rules.seconds_to_ticks(Rules.FEINT_COOLDOWN)
				_event("feint", fighter.side, {"move": move.id, "ticks": move.windup_ticks - Rules.FEINT_BREAK_TICKS})
			else:
				_walk(fighter, foe, intent.get("move", Vector2.ZERO))
			var walking := fighter.velocity / maxf(fighter.move_speed, 0.1)
			_turn(fighter, to_foe + walking.limit_length(1.0) * Rules.MOVE_FACING_WEIGHT,
				Rules.AIM_TURN_RATE if fighter.action == Fighter.Action.WINDUP else Rules.TURN_RATE)


## Whether `fighter` can see `foe` over the terrain (chest to chest).
func can_see(fighter: Fighter, foe: Fighter) -> bool:
	return terrain.clear_line(Vector3(fighter.position.x, fighter.ground + Rules.CHEST_HEIGHT, fighter.position.y),
		Vector3(foe.position.x, foe.ground + Rules.CHEST_HEIGHT, foe.position.y))


## Whether `move` could connect from `fighter` to `foe` right now, terrain aside from range:
## a clear line for projectiles, a small enough height difference for melee and area moves.
func can_reach(fighter: Fighter, foe: Fighter, move: BattleMove) -> bool:
	match move.kind:
		BattleMove.Kind.PROJECTILE, BattleMove.Kind.DEBUFF, BattleMove.Kind.STATUS:
			return can_see(fighter, foe)
		BattleMove.Kind.MELEE:
			return absf(foe.ground - fighter.ground) <= Rules.MELEE_HEIGHT
		BattleMove.Kind.AREA:
			return absf(foe.ground - fighter.ground) <= Rules.AREA_HEIGHT
	return true


## Gap between two fighters' hitboxes.
static func _gap(fighter: Fighter, foe: Fighter) -> float:
	return fighter.position.distance_to(foe.position) - fighter.radius - foe.radius


func _walk(fighter: Fighter, foe: Fighter, direction: Vector2) -> void:
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	_drift(fighter, foe, direction * fighter.current_move_speed())


## Eases the fighter's velocity toward `target` (m/s) at Rules.ACCELERATION and moves it. The
## velocity kept is what it actually moved, so walls and the foe's body stop it.
func _drift(fighter: Fighter, foe: Fighter, target: Vector2) -> void:
	var rate := Rules.ACCELERATION * fighter.agility
	if fighter.glides and target.length_squared() < fighter.velocity.length_squared():
		rate *= Rules.GLIDE_BRAKING
	fighter.velocity = fighter.velocity.move_toward(target, rate / Rules.TICK_RATE)
	var before := fighter.position
	_slide(fighter, foe, fighter.velocity / Rules.TICK_RATE)
	fighter.velocity = (fighter.position - before) * Rules.TICK_RATE


## Turns the fighter's facing toward `direction` by at most `degrees_per_second` this tick.
static func _turn(fighter: Fighter, direction: Vector2, degrees_per_second: float) -> void:
	if direction.length_squared() < 1e-8:
		return
	var step := deg_to_rad(degrees_per_second * fighter.agility) / Rules.TICK_RATE
	fighter.facing = fighter.facing.rotated(clampf(fighter.facing.angle_to(direction), -step, step)).normalized()


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
	next = terrain.push_out(next, fighter.radius, fighter.ground, fighter.climb)
	if next.length() > limit:
		next = next.normalized() * limit
	fighter.position = next
	fighter.ground = terrain.height_at(next)


func _release(fighter: Fighter, foe: Fighter) -> void:
	var move := fighter.moves[fighter.action_move]
	fighter.action = Fighter.Action.RECOVERY
	fighter.action_ticks = move.recovery_ticks
	if move.is_self():
		if move.kind == BattleMove.Kind.HEAL:
			_heal(fighter, roundi(fighter.max_hp * conditions.heal_share(fighter, move)), move.id)
		elif move.kind == BattleMove.Kind.ARENA:
			_set_weather(fighter, move.weather, {"move": move.id})
		else:
			_boost(fighter, move.boosts, move.id)
	else:
		var hits := _roll_hits(fighter, move)
		var parried := _strike(fighter, foe, fighter.action_move)
		var interval := Rules.seconds_to_ticks(Rules.MULTI_HIT_INTERVAL)
		for i in range(1, hits if not parried else 1):
			fighter.followups.append({"ticks": i * interval, "move": fighter.action_move, "last": i == hits - 1})
		if move.recharges:
			_event("recharge", fighter.side, {"move": move.id})
		if move.self_destructs:
			_hurt(fighter, fighter.hp, "self_destruct", {"move": move.id})


## One strike of a damaging move, or the launch of a projectile. Returns whether the foe
## parried it.
func _strike(fighter: Fighter, foe: Fighter, move_index: int) -> bool:
	var move := fighter.moves[move_index]
	match move.kind:
		BattleMove.Kind.MELEE, BattleMove.Kind.AREA:
			var reach := Rules.MELEE_REACH if move.kind == BattleMove.Kind.MELEE else Rules.AREA_RADIUS
			if move.kind == BattleMove.Kind.AREA:
				_event("blast", fighter.side, {"move": move.id})
			var reach_up := Rules.MELEE_HEIGHT if move.kind == BattleMove.Kind.MELEE else Rules.AREA_HEIGHT
			if _gap(fighter, foe) > reach or foe.is_knocked_out() or absf(foe.ground - fighter.ground) > reach_up:
				_event("miss", fighter.side, {"move": move.id})
			elif foe.is_invulnerable():
				_event("miss", fighter.side, {"move": move.id})
				_event("dodged", foe.side, {"move": move.id})
			elif foe.guards_against(fighter.position - foe.position):
				_guarded(fighter, foe, move)
				return move.kind == BattleMove.Kind.MELEE
			else:
				_hit(fighter, foe, move)
		_:
			_projectile_count += 1
			# Aimed along the facing, rising or falling to reach the foe's chest at its distance.
			var start := fighter.position + fighter.facing * fighter.radius
			var speed := conditions.projectile_speed(fighter, move) / Rules.TICK_RATE
			if move.physical:
				speed *= float(fighter.ability_effect.get("physical_projectile_speed", 1.0))
			var ticks_to_foe := maxf(start.distance_to(foe.position) / speed, 1.0)
			projectiles.append({
				"id": _projectile_count,
				"owner": fighter.side,
				"move": move_index,
				"position": start,
				"velocity": fighter.facing * speed,
				"height": fighter.ground + Rules.CHEST_HEIGHT,
				"rise": (foe.ground - fighter.ground) / ticks_to_foe,
				"travelled": 0.0,
			})
			_event("fire", fighter.side, {"move": move.id})
	return false


## Hits for one use: fixed, or 2-5 with the main-series weights (always the most with Skill Link).
func _roll_hits(fighter: Fighter, move: BattleMove) -> int:
	if move.hits_min == move.hits_max:
		return move.hits_min
	if fighter.ability_effect.get("skill_link", false):
		return move.hits_max
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
		var height: float = projectile.height
		var level := absf(height - (target.ground + Rules.CHEST_HEIGHT)) <= Rules.PROJECTILE_VERTICAL_REACH
		if closest.distance_to(target.position) <= target.radius + Rules.PROJECTILE_RADIUS and not target.is_knocked_out() and level:
			if target.guards_against(-(projectile.velocity as Vector2)):
				_guarded(owner, target, move)
				continue
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
		projectile.height = height + float(projectile.rise)
		projectile.travelled += (projectile.velocity as Vector2).length()
		if terrain.height_at(end) > projectile.height:
			_event("blocked", owner.side, {"move": move.id, "position": [end.x, end.y], "height": projectile.height})
			_event("miss", owner.side, {"move": move.id})
		elif projectile.travelled < Rules.PROJECTILE_RANGE * 1.5 and end.length() < Rules.ARENA_RADIUS:
			remaining.append(projectile)
		else:
			_event("miss", owner.side, {"move": move.id})
	projectiles = remaining


func _hit(attacker: Fighter, defender: Fighter, move: BattleMove) -> void:
	var outcome := damage(attacker, defender, move, _data, _random)
	outcome.damage = maxi(1, floori(outcome.damage * Rules.overtime_factor(tick)))
	var immune := Abilities.immune(defender, move)
	var dealt := mini(outcome.damage, defender.hp)
	var lethal: bool = dealt >= defender.hp and defender.hp > 1
	var holds: bool = lethal and defender.ability_effect.get("sturdy", false) and not defender.sturdy_used
	# Focus Sash: from full HP, the first knockout blow leaves 1 HP.
	var sash: bool = lethal and not holds and defender.hp == defender.max_hp and defender.item_effect.get("focus_sash", false) \
		and not defender.item_used
	if holds or sash:
		dealt = defender.hp - 1
		defender.sturdy_used = defender.sturdy_used or holds
		defender.item_used = defender.item_used or sash
	defender.hp -= dealt
	_event("hit", attacker.side, {"move": move.id, "damage": dealt if holds or sash else outcome.damage, "crit": outcome.crit,
		"effectiveness": outcome.effectiveness, "hp": defender.hp})
	if holds:
		_ability_event(defender)
	if sash:
		_item_event(defender)
	if immune and Abilities.absorbs(defender, move):
		_absorb(defender, move)
	_ability_on_hit(attacker, defender, move)
	_item_on_hit(attacker, defender, move, dealt)
	if defender.is_knocked_out():
		_event("knockout", defender.side, {})
	else:
		var push := (defender.position - attacker.position).normalized()
		defender.velocity += push * Rules.knockback_speed(float(dealt) / defender.max_hp, defender.weight_kg)
		if defender.action == Fighter.Action.WINDUP and defender.moves[defender.action_move].kind == BattleMove.Kind.HEAL:
			defender.action = Fighter.Action.READY
			defender.action_ticks = 0
			_event("interrupt", defender.side, {"move": defender.moves[defender.action_move].id})
		if defender.status == "slp" or (defender.status == "frz" and move.type == "Fire"):
			_end_status(defender)
		if not immune and Abilities.secondaries_apply(attacker, defender):
			for effect in move.secondaries:
				if _random.chance(effect.chance / 100.0 * Abilities.secondary_chance_factor(attacker)):
					_apply_effect(attacker, defender, effect, move.id)
	if move.drain_share > 0.0 and not attacker.is_knocked_out():
		_heal(attacker, maxi(1, roundi(dealt * move.drain_share)), move.id)
	if move.recoil_share > 0.0 and not Abilities.no_recoil(attacker):
		var recoil := maxi(1, roundi(dealt * move.recoil_share))
		_hurt(attacker, recoil, "recoil", {"move": move.id})
	if not move.self_boosts.is_empty() and not attacker.is_knocked_out():
		_boost(attacker, move.self_boosts, move.id)


## A hit stopped by the defender's guard: no damage or effects. Parrying a melee strike
## staggers the attacker and drops its remaining multi-hit strikes.
func _guarded(attacker: Fighter, defender: Fighter, move: BattleMove) -> void:
	defender.guard_blocked = true
	var parry := move.kind == BattleMove.Kind.MELEE
	_event("miss", attacker.side, {"move": move.id})
	_event("guarded", defender.side, {"move": move.id, "parry": parry})
	if parry:
		attacker.followups.clear()
		if attacker.action == Fighter.Action.READY or attacker.action == Fighter.Action.RECOVERY:
			attacker.action = Fighter.Action.RECOVERY
			attacker.action_ticks = maxi(attacker.action_ticks, Rules.seconds_to_ticks(Rules.PARRY_STAGGER))


## Reports that `fighter`'s ability took effect, so the view can name it.
func _ability_event(fighter: Fighter, details := {}) -> void:
	details.merge({"ability": fighter.ability, "name": Abilities.display_name(fighter.ability)})
	_event("ability", fighter.side, details)


## An absorbing ability (Water Absorb, Sap Sipper, Flash Fire) taking a hit of its type.
func _absorb(fighter: Fighter, move: BattleMove) -> void:
	if fighter.is_knocked_out():
		return
	var entry := fighter.ability_effect
	_ability_event(fighter)
	if entry.has("absorb_heal"):
		_heal(fighter, maxi(1, roundi(fighter.max_hp * float(entry.absorb_heal))), move.id)
	if entry.has("absorb_boosts"):
		_boost(fighter, entry.absorb_boosts, fighter.ability)
	if entry.has("absorb_power"):
		fighter.flash_fire_ticks = Rules.seconds_to_ticks(Abilities.ABILITY_SECONDS)


## Abilities that answer a hit: contact punishers on the attacker (melee strikes), and the
## defender's own reactions (Justified, Weak Armor).
func _ability_on_hit(attacker: Fighter, defender: Fighter, move: BattleMove) -> void:
	var entry := defender.ability_effect
	if move.kind == BattleMove.Kind.MELEE and not attacker.is_knocked_out():
		var statuses: Array = entry.get("contact_status", [])
		if not statuses.is_empty() and _random.chance(Abilities.CONTACT_STATUS_CHANCE):
			var status: String = statuses[0] if statuses.size() == 1 else statuses[_random.next_u32() % statuses.size()]
			if attacker.status.is_empty():
				_ability_event(defender)
				_inflict(attacker, status, defender)
		if entry.has("contact_damage") and not Abilities.magic_guard(attacker):
			_ability_event(defender)
			_hurt(attacker, maxi(1, roundi(attacker.max_hp * float(entry.contact_damage))), "ability_damage",
				{"ability": defender.ability})
	if defender.is_knocked_out():
		return
	var by_type: Dictionary = entry.get("hit_by_type", {})
	if not by_type.is_empty() and move.type == by_type.type:
		_ability_event(defender)
		_boost(defender, by_type.boosts, defender.ability)
	var on_physical: Dictionary = entry.get("on_physical_hit", {})
	if not on_physical.is_empty() and move.physical and defender.weak_armor_ticks == 0:
		defender.weak_armor_ticks = Rules.seconds_to_ticks(float(on_physical.seconds))
		_ability_event(defender)
		_boost(defender, on_physical.boosts, defender.ability)


## Reports that `fighter`'s held item took effect (or was used up), so the view can name it.
func _item_event(fighter: Fighter, details := {}) -> void:
	details.merge({"item": fighter.item, "name": Items.display_name(fighter.item)})
	_event("item", fighter.side, details)


## Items that act on a hit landing: the attacker's Life Orb cost and Shell Bell, the
## defender's Rocky Helmet (melee strikes) and Sitrus Berry.
func _item_on_hit(attacker: Fighter, defender: Fighter, move: BattleMove, dealt: int) -> void:
	var held := attacker.item_effect
	if held.has("heal_from_damage") and dealt > 0 and not attacker.is_knocked_out():
		_heal(attacker, maxi(1, roundi(dealt * float(held.heal_from_damage))), attacker.item)
	if held.has("hit_cost") and not Abilities.magic_guard(attacker):
		_hurt(attacker, maxi(1, roundi(attacker.max_hp * float(held.hit_cost))), "item_damage", {"item": attacker.item})
	if move.kind == BattleMove.Kind.MELEE and defender.item_effect.has("contact_damage") and not Abilities.magic_guard(attacker):
		_item_event(defender)
		_hurt(attacker, maxi(1, roundi(attacker.max_hp * float(defender.item_effect.contact_damage))), "item_damage",
			{"item": defender.item})
	_check_berry(defender)


## A Sitrus Berry restoring HP once its holder falls to half or less.
func _check_berry(fighter: Fighter) -> void:
	var held := fighter.item_effect
	if not held.has("berry_heal") or fighter.item_used or fighter.is_knocked_out():
		return
	if fighter.hp <= fighter.max_hp * float(held.berry_below):
		fighter.item_used = true
		_item_event(fighter)
		_heal(fighter, maxi(1, roundi(fighter.max_hp * float(held.berry_heal))), fighter.item)


## A Lum Berry curing a status condition or confusion the moment it's inflicted, once.
func _check_lum(fighter: Fighter) -> void:
	if not fighter.item_effect.get("cures_status", false) or fighter.item_used:
		return
	fighter.item_used = true
	_item_event(fighter)
	if not fighter.status.is_empty():
		_end_status(fighter)
	if fighter.confusion_ticks > 0:
		fighter.confusion_ticks = 0
		_event("status_end", fighter.side, {"status": "confusion"})


## Items that act over time, once a second: Leftovers and Black Sludge (which hurts a holder
## of the wrong type).
func _tick_item(fighter: Fighter) -> void:
	var held := fighter.item_effect
	if not held.has("heal_per_second") or tick % Rules.TICK_RATE != 0:
		return
	var share := float(held.heal_per_second)
	if held.has("needs_type") and not held.needs_type in fighter.types:
		if not Abilities.magic_guard(fighter):
			_hurt(fighter, maxi(1, roundi(fighter.max_hp * share)), "item_damage", {"item": fighter.item})
	else:
		_heal(fighter, maxi(1, roundi(fighter.max_hp * share)), fighter.item, "regen")


## Abilities that act over time, once per tick: Intimidate (at the start and every
## INTIMIDATE_SECONDS), Speed Boost, and the timers on Flash Fire and Weak Armor.
func _tick_abilities(fighter: Fighter, foe: Fighter) -> void:
	var entry := fighter.ability_effect
	if entry.is_empty():
		return
	fighter.flash_fire_ticks = maxi(0, fighter.flash_fire_ticks - 1)
	fighter.weak_armor_ticks = maxi(0, fighter.weak_armor_ticks - 1)
	if entry.get("intimidate", false):
		fighter.intimidate_ticks -= 1
		if fighter.intimidate_ticks <= 0:
			fighter.intimidate_ticks = Rules.seconds_to_ticks(Abilities.INTIMIDATE_SECONDS)
			_ability_event(fighter)
			if foe.ability_effect.get("intimidate_immune", false):
				_ability_event(foe)
			else:
				_boost(foe, {"atk": -1}, fighter.ability, fighter)
	var speed_boost: Dictionary = entry.get("speed_boost", {})
	if not speed_boost.is_empty():
		fighter.speed_boost_ticks += 1
		if fighter.speed_boost_ticks >= Rules.seconds_to_ticks(float(speed_boost.seconds)):
			fighter.speed_boost_ticks = 0
			if fighter.boosts.spe < int(speed_boost.max):
				_ability_event(fighter)
				_boost(fighter, {"spe": 1}, fighter.ability)


## The conditions a battle starts with, on its first tick: the arena's or spec's weather, then
## weather-setting abilities, the faster fighter's first, so the slower one's weather wins
## (a tie goes to the battle's random stream).
func _start_conditions() -> void:
	if not conditions.weather.is_empty():
		_event("weather", -1, {"weather": conditions.weather, "seconds": -1})
	var setters: Array[Fighter] = []
	for fighter in fighters:
		if not Abilities.sets_weather(fighter).is_empty():
			setters.append(fighter)
	if setters.size() == 2:
		var a_speed := setters[0].stat("spe")
		var b_speed := setters[1].stat("spe")
		if a_speed < b_speed or (a_speed == b_speed and _random.chance(0.5)):
			setters.reverse()
	for fighter in setters:
		_ability_event(fighter)
		_set_weather(fighter, Abilities.sets_weather(fighter), {"ability": fighter.ability})


## Sets a weather from `setter`'s move or ability (`source`: {"move"} or {"ability"}), for its
## usual time or longer with the matching rock.
func _set_weather(setter: Fighter, weather: String, source: Dictionary) -> void:
	var ticks := ArenaConditions.weather_ticks_for(setter, weather)
	var renewed := conditions.weather == weather
	conditions.set_weather(weather, ticks)
	var details := {"weather": weather, "seconds": ticks / float(Rules.TICK_RATE), "renewed": renewed}
	details.merge(source)
	_event("weather", setter.side, details)


## The weather's effects on a fighter, once a second: sandstorm damage, the ability's healing
## or damage (Rain Dish, Dry Skin, Solar Power), and Hydration curing a status in rain.
func _tick_weather(fighter: Fighter) -> void:
	if tick % Rules.TICK_RATE != 0:
		return
	var weather := conditions.weather_for(fighter)
	if weather.is_empty():
		return
	var change := ArenaConditions.hp_per_second(fighter.types, fighter.ability_effect, weather)
	if change < 0.0:
		_hurt(fighter, maxi(1, roundi(fighter.max_hp * -change)), "weather_damage", {"weather": weather})
	elif change > 0.0:
		_heal(fighter, maxi(1, roundi(fighter.max_hp * change)), fighter.ability, "regen")
	if not fighter.status.is_empty() and str(fighter.ability_effect.get("weather_cures", "")) == weather and not fighter.is_knocked_out():
		_ability_event(fighter)
		_end_status(fighter)


## A debuff or status projectile reaching its target.
func _land(attacker: Fighter, defender: Fighter, move: BattleMove) -> void:
	_event("landed", attacker.side, {"move": move.id})
	_apply_effect(attacker, defender, {"boosts": move.boosts, "status": move.status, "confuses": move.confuses}, move.id)


func _apply_effect(attacker: Fighter, defender: Fighter, effect: Dictionary, move_id: String) -> void:
	if not str(effect.get("status", "")).is_empty():
		_inflict(defender, effect.status, attacker)
	if effect.get("confuses", false) and defender.confusion_ticks == 0:
		if Abilities.status_immune(defender, "confusion"):
			_ability_event(defender)
		else:
			defender.confusion_ticks = Rules.seconds_to_ticks(Rules.CONFUSION_SECONDS)
			_event("status", defender.side, {"status": "confusion"})
			_check_lum(defender)
	if not effect.get("boosts", {}).is_empty():
		_boost(defender, effect.boosts, move_id, attacker)
	if not effect.get("self_boosts", {}).is_empty():
		_boost(attacker, effect.self_boosts, move_id)


## Gives a major status unless the fighter already has one or its type or ability is immune.
## `source` is the foe that caused it, if any (Synchronize passes it back).
func _inflict(fighter: Fighter, status: String, source: Fighter = null) -> void:
	if not fighter.status.is_empty() or fighter.is_knocked_out():
		return
	for type: String in Rules.STATUS_IMMUNITIES.get(status, []):
		if type in fighter.types:
			return
	if Abilities.status_immune(fighter, status):
		_ability_event(fighter)
		return
	if conditions.blocks_status(fighter, status):
		return
	fighter.status = status
	fighter.toxic_level = 0
	if status == "slp" or status == "frz":
		fighter.followups.clear()
	match status:
		"slp":
			var seconds := _random.range_float(Rules.SLEEP_MIN_SECONDS, Rules.SLEEP_MAX_SECONDS)
			fighter.status_ticks = Rules.seconds_to_ticks(seconds * float(fighter.ability_effect.get("sleep_factor", 1.0)))
		"frz":
			fighter.status_ticks = Rules.seconds_to_ticks(Rules.FREEZE_SECONDS)
		_:
			fighter.status_ticks = Rules.seconds_to_ticks(Rules.STATUS_SECONDS)
	_event("status", fighter.side, {"status": status})
	_check_lum(fighter)
	if source != null and fighter.ability_effect.get("synchronize", false) and status in ["brn", "par", "psn", "tox"]:
		_ability_event(fighter)
		_inflict(source, status)


func _end_status(fighter: Fighter) -> void:
	_event("status_end", fighter.side, {"status": fighter.status})
	fighter.status = ""
	fighter.status_ticks = 0


## Changes stat stages within +-6 and reports the changes that took effect. `foe` is the foe
## making the change, if any: abilities can block its drops (Clear Body) or answer them
## (Defiant).
func _boost(fighter: Fighter, changes: Dictionary, move_id: String, foe: Fighter = null) -> void:
	if foe != null:
		var allowed := Abilities.allowed_drops(fighter, changes)
		if allowed.size() < changes.size():
			_ability_event(fighter)
		changes = allowed
	var applied := {}
	for stat: String in changes:
		var before: int = fighter.boosts[stat]
		fighter.boosts[stat] = clampi(before + int(changes[stat]), -Rules.MAX_STAGE, Rules.MAX_STAGE)
		if fighter.boosts[stat] != before:
			applied[stat] = fighter.boosts[stat] - before
	if not applied.is_empty():
		fighter.stage_ticks = 0
		_event("boost", fighter.side, {"boosts": applied, "move": move_id})
	var answer: Dictionary = fighter.ability_effect.get("on_lowered", {})
	if foe != null and not answer.is_empty() and applied.values().any(func(stages: int) -> bool: return stages < 0):
		_ability_event(fighter)
		_boost(fighter, answer, fighter.ability)


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


## Restores HP, reported as `type`: "heal", or "regen" for the small steady healing of
## items like Leftovers, which the view doesn't call out.
func _heal(fighter: Fighter, amount: int, move_id: String, type := "heal") -> void:
	var healed := mini(amount, fighter.max_hp - fighter.hp)
	if healed > 0:
		fighter.hp += healed
		_event(type, fighter.side, {"amount": healed, "hp": fighter.hp, "move": move_id})


## Takes HP outside a hit (status damage, recoil, confusion), reporting it as `type`.
func _hurt(fighter: Fighter, amount: int, type: String, details: Dictionary) -> void:
	if fighter.is_knocked_out():
		return
	fighter.hp = maxi(0, fighter.hp - amount)
	details.merge({"damage": amount, "hp": fighter.hp})
	_event(type, fighter.side, details)
	if fighter.is_knocked_out():
		_event("knockout", fighter.side, {})
	else:
		_check_berry(fighter)


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
		var entry := fighter.ability_effect
		if entry.has("shed_skin") and _random.chance(float(entry.shed_skin)):
			_ability_event(fighter)
			_end_status(fighter)
			return
		# Magic Guard takes no damage from conditions; Poison Heal turns poison into healing.
		var harmed := not Abilities.magic_guard(fighter)
		if fighter.status in ["psn", "tox"] and entry.get("poison_heal", false):
			harmed = false
			_heal(fighter, maxi(1, roundi(fighter.max_hp * Abilities.POISON_HEAL)), fighter.ability)
		match fighter.status:
			"brn":
				if harmed:
					_hurt(fighter, maxi(1, roundi(fighter.max_hp * Rules.BURN_DAMAGE)), "status_damage", {"status": "brn"})
			"psn":
				if harmed:
					_hurt(fighter, maxi(1, roundi(fighter.max_hp * Rules.POISON_DAMAGE)), "status_damage", {"status": "psn"})
			"tox":
				fighter.toxic_level += 1
				if harmed:
					_hurt(fighter, maxi(1, roundi(fighter.max_hp * Rules.TOXIC_STEP * fighter.toxic_level)), "status_damage", {"status": "tox"})
			"par":
				if _random.chance(Rules.PARALYSIS_STUN_CHANCE):
					fighter.stun_ticks = Rules.seconds_to_ticks(Rules.PARALYSIS_STUN_SECONDS)
					_event("stunned", fighter.side, {})
	if fighter.status_ticks <= 0 and not fighter.is_knocked_out():
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
## stats after stat stages, abilities, items and burn. Fixed-damage moves ignore stats, type
## and crits.
static func damage(attacker: Fighter, defender: Fighter, move: BattleMove, data: BattleData, random: SimRandom) -> Dictionary:
	if move.fixed_damage > 0:
		return {"damage": move.fixed_damage, "crit": false, "effectiveness": 1.0}
	var parts := damage_parts(attacker, defender, move, data)
	var crit := random.chance(Rules.CRIT_CHANCE)
	var roll := random.range_float(Rules.ROLL_MIN, Rules.ROLL_MAX)
	var total: float = parts.base * parts.factor * (Rules.CRIT_MULTIPLIER if crit else 1.0) * roll
	return {"damage": maxi(1, floori(total)), "crit": crit, "effectiveness": parts.effectiveness}


## A hit's damage before luck, shared with the AI's estimates: the formula's base (power after
## abilities, stats after stages), the multipliers on it (STAB, type, the defender's ability)
## and the compressed effectiveness. An ability immunity counts as a type immunity (§9.9).
static func damage_parts(attacker: Fighter, defender: Fighter, move: BattleMove, data: BattleData) -> Dictionary:
	var attack := move.attack_stat(attacker, defender)
	var defense := defender.stat(move.defensive_stat)
	var power := move.power * Abilities.power_factor(attacker, move)
	var base := floorf(floorf(floorf(2.0 * Rules.LEVEL / 5.0 + 2.0) * power * attack / defense) / 50.0) + 2.0
	var stab := Abilities.stab(attacker) if move.type in attacker.types else 1.0
	var main_series := Abilities.effectiveness(attacker, defender, move, data.effectiveness(move.type, defender.types))
	var effectiveness := Rules.compressed_effectiveness(main_series)
	var factor := stab * effectiveness * Abilities.taken_factor(defender, move, main_series) * Items.power_factor(attacker, move, main_series) 		* attacker.arena.damage_factor(attacker, defender, move)
	return {"base": base, "factor": factor,
		"effectiveness": effectiveness}


func _check_end() -> void:
	var a_down := fighters[0].is_knocked_out()
	var b_down := fighters[1].is_knocked_out()
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
	_state.resize(FIGHTER_STATE_SIZE * 2 + 2 + projectiles.size() * 3)
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
		_state[i + 17] = fighter.velocity.x
		_state[i + 18] = fighter.velocity.y
		_state[i + 19] = fighter.facing.x
		_state[i + 20] = fighter.facing.y
		_state[i + 21] = fighter.ground
		_state[i + 22] = fighter.feint_cooldown
		_state[i + 23] = 1.0 if fighter.feinting else 0.0
		_state[i + 24] = fighter.guard_cooldown
		_state[i + 25] = 1.0 if fighter.guard_blocked else 0.0
		_state[i + 26] = fighter.flash_fire_ticks
		_state[i + 27] = fighter.intimidate_ticks
		_state[i + 28] = fighter.speed_boost_ticks
		_state[i + 29] = fighter.weak_armor_ticks
		_state[i + 30] = 1.0 if fighter.sturdy_used else 0.0
		_state[i + 31] = 1.0 if fighter.item_used else 0.0
		i += FIGHTER_STATE_SIZE
	_state[i] = ArenaConditions.WEATHERS.find(conditions.weather)
	_state[i + 1] = conditions.weather_ticks
	i += 2
	for projectile in projectiles:
		_state[i] = projectile.position.x
		_state[i + 1] = projectile.position.y
		_state[i + 2] = projectile.height
		i += 3
	_hash.update(_state.to_byte_array())


func _event(type: String, side: int, details: Dictionary) -> void:
	var event := {"tick": tick, "type": type, "side": side}
	event.merge(details)
	events.append(event)
