class_name Battle
extends RefCounted
## The real-time battle simulation (concepts_brief.md §9, §10): plain objects, a fixed tick,
## simple geometric hit tests, seeded random streams and no engine physics. The same spec
## always produces the same battle on the same Godot build and platform.
##
## Each tick: controllers produce intents, then both sides act in an order that alternates
## every tick, projectiles move, and the battle checks for a knockout or the time cap.
##
## A side brings a team of 1-Rules.MAX_TEAM Pokémon (§9.1), one out at a time: `teams` holds
## every member and `fighters` each side's one out now. After a knockout with more to come,
## the side's next one is sent out (Rules.KNOCKOUT_LULL_SECONDS later, at its start spot); the
## battle ends when a side has no one left.
##
## Doubles (M17, a spec's "doubles": true) puts two of each side's team out at once, each in
## a place (0 or 1) and locked onto a foe's place (target_of). `fighters` then holds four, one per
## place and side at index place * 2 + side (index_of), so fighters[side] is always a side's
## first and singles reads exactly as before. Each fighter out has its own controller.

## SIDE_A2 and SIDE_B2 are the AI streams of each side's second fighter in doubles.
enum Stream { BATTLE, SIDE_A, SIDE_B, COSMETIC, TERRAIN, SIDE_A2, SIDE_B2 }
enum Result { ONGOING, WIN_A, WIN_B, DRAW }

var tick := 0
var result := Result.ONGOING
## The fighters out now, indexed by index_of (by side in singles).
var fighters: Array[Fighter] = []
## Whether two of each side's team are out at once (M17).
var doubles := false
## Each side's whole team in the spec's order (Fighter.slot), the fighters out included.
var teams: Array = [[], []]
## The tick overtime starts in the stretch since the last send-out after a knockout (or the
## start), and the HP factor team battles scale its length and every fighter's HP by.
var overtime_tick := 0
var pace := 1.0
var projectiles: Array[Dictionary] = []
## Events for presentation and highlight picking: {"tick", "type", "side", ...}.
var events: Array[Dictionary] = []
var spec: Dictionary
## The arena preset (Arenas), from the spec's "arena" or else the fighters' types and the seed.
var arena := ""
## The arena's ground (§9.8), from its field and the seed.
var terrain: Terrain
## The arena conditions (§9.11): the weather, surge and screens, shared with both fighters.
var conditions := ArenaConditions.new()
## With record_intents set (battles with a player), every tick's intents per fighter out
## (index_of), as [move x, move y, use, dodge x, dodge y, feint, guard, switch] and, when it
## names one, the target; a ReplayController plays them back.
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
## Values hashed per side for team battles: the slot out, the send-out countdown, the shield,
## the switch cooldown and the layers of each entry hazard.
const TEAM_STATE_SIZE := 8
## Values hashed per place in doubles: its slot out, send-out countdown, shield and target, and
## its fighter's Helping Hand and Dragon Cheer timers and whether its move is helped (then per
## side, the pull's and Wide Guard's ticks left).
const PLACE_STATE_SIZE := 7
## Values hashed for the field conditions and each side's side conditions.
const FIELD_STATE_SIZE := 10
var _state := PackedFloat64Array()
## Projectiles fired so far; each gets the next number as a stable id.
var _projectile_count := 0
## Per place (index_of), ticks until its next Pokémon is sent out after a knockout (0 for none
## pending), and the team slot picked to send out there (-1 for none: the first member left).
var _send_out_ticks := PackedInt32Array([0, 0])
var _picks := PackedInt32Array([-1, -1])
## Per side, ticks until it can switch again.
var _switch_cooldown := PackedInt32Array([0, 0])
## Set by a knockout with more to come: projectiles in flight vanish at the end of the tick (in
## doubles only those aimed at the fighters knocked out, by index).
var _drop_projectiles := false
var _dropped_targets: Array[int] = []
## Doubles' ally moves, per side: Follow Me's or Rage Powder's pull ({"fighter", "ticks",
## "powder"}, {} for none) and ticks left of Wide Guard.
var _redirects: Array[Dictionary] = [{}, {}]
var _wide_guard := PackedInt32Array([0, 0])
## Whether the state hashed includes the teams' (only when a side has more than one member,
## so one-on-one battles hash exactly as before).
var _hash_teams := false


## `spec` = {"seed": int, "fighters": [{"species", "moves"?: [ids], "radius"?}, x2] (one per
## side; a side's entry may instead hold "team": [members like that], 1-Rules.MAX_TEAM of them),
## "doubles"?: true for two out a side (teams of Rules.MIN_DOUBLES_TEAM or more),
## "arena"?: preset, "weather"?: a starting weather ("" for none, else the preset's),
## "rules_version"?: int, "data_versions"?: {source: SHA-256}}. Without
## "moves" a fighter gets its species' standard moveset (Movesets). The
## hitbox radius comes from the spec, else the roster, else Fighter.DEFAULT_RADIUS; with a
## roster loaded, species outside it are rejected. A spec that names a rules or data version
## other than these is rejected, since it would play as a different battle.
## Controllers, one per fighter out (in index_of order), are objects with decide(battle, index)
## -> {"move": Vector2, "use": int, "dodge": Vector2 (zero for none), "feint": int (a move to
## feint), "guard": bool, "switch": int, "target": int (a foe's place, doubles)}; each owns its
## random stream (see random_stream()).
## Returns {"battle": Battle} or {"error": String}.
static func create(battle_spec: Dictionary, data: BattleData, controllers: Array) -> Dictionary:
	var version_problem := _version_problem(battle_spec, data)
	if not version_problem.is_empty():
		return {"error": version_problem}
	var entries: Array = battle_spec.get("fighters", [])
	var per_side := 2 if battle_spec.get("doubles", false) == true else 1
	if entries.size() != 2 or controllers.size() != 2 * per_side:
		return {"error": "a battle needs exactly two sides (fighters) and %d controllers" % (2 * per_side)}
	var members: Array = []
	for entry: Dictionary in entries:
		var team := members_of(entry)
		if team.is_empty() or team.size() > Rules.MAX_TEAM:
			return {"error": "a team has 1-%d Pokémon, not %d" % [Rules.MAX_TEAM, team.size()]}
		if team.size() < per_side:
			return {"error": "a doubles team has %d-%d Pokémon, not %d" % [Rules.MIN_DOUBLES_TEAM, Rules.MAX_TEAM, team.size()]}
		members.append(team)
	var battle := Battle.new()
	battle.spec = battle_spec
	battle.doubles = per_side == 2
	battle._data = data
	battle._controllers = controllers
	battle._random = SimRandom.stream(int(battle_spec.seed), Stream.BATTLE)
	var team_size := maxi(members[0].size(), members[1].size())
	battle._hash_teams = team_size > 1
	battle.pace = Rules.doubles_hp_factor() if battle.doubles else Rules.team_hp_factor(team_size)
	battle._start_stretch(0)
	var types: Array = []
	for team: Array in members:
		for entry: Dictionary in team:
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
		for slot in members[side].size():
			var made := _make_fighter(members[side][slot], side, data)
			if made.has("error"):
				return made
			var fighter: Fighter = made.fighter
			fighter.slot = slot
			if team_size > 1:
				fighter.max_hp = maxi(1, roundi(fighter.max_hp * battle.pace))
				fighter.hp = fighter.max_hp
			fighter.arena = battle.conditions
			battle.teams[side].append(fighter)
		# The leads' send-out starts the switch cooldown like any other.
		if team_size > 1:
			battle._switch_cooldown[side] = Rules.seconds_to_ticks(Rules.SWITCH_COOLDOWN_SECONDS)
	for place in per_side:
		for side in 2:
			var lead: Fighter = battle.teams[side][place]
			lead.place = place
			lead.target_place = place
			battle._place_at_start(lead)
			battle.fighters.append(lead)
	battle._link_allies()
	var out := battle.fighters.size()
	battle._send_out_ticks.resize(out)
	battle._send_out_ticks.fill(0)
	battle._picks.resize(out)
	battle._picks.fill(-1)
	battle.intent_log.resize(out)
	for index in out:
		battle.intent_log[index] = []
	battle._count_benches()
	battle._hash.start(HashingContext.HASH_SHA256)
	return {"battle": battle}


## A side's team members from its spec entry: its "team", or the entry itself for one.
static func members_of(entry: Dictionary) -> Array:
	return entry.team if entry.get("team") is Array else [entry]


## One team member from its spec entry: {"fighter": Fighter} or {"error": String}.
static func _make_fighter(entry: Dictionary, side: int, data: BattleData) -> Dictionary:
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
	return {"fighter": fighter}


## Restarts the overtime clock at `from`: overtime and the time cap come as long after it as in
## a one-on-one battle.
func _start_stretch(from: int) -> void:
	overtime_tick = from + Rules.seconds_to_ticks(Rules.OVERTIME_SECONDS)
	_time_cap_ticks = from + Rules.seconds_to_ticks(Rules.TIME_CAP_SECONDS)


## Puts a fighter on its side's start spot (in doubles, Rules.DOUBLES_SPREAD to one side of it by
## place, across from the foe in the same place), facing the other side's.
func _place_at_start(fighter: Fighter) -> void:
	var across := ((-1.0 if fighter.place == 0 else 1.0) * Rules.DOUBLES_SPREAD) if doubles else 0.0
	fighter.position = Vector2(across, (-0.5 if fighter.side == 0 else 0.5) * Rules.START_DISTANCE)
	fighter.facing = Vector2(0, 1 if fighter.side == 0 else -1)
	fighter.velocity = Vector2.ZERO
	fighter.ground = terrain.height_at(fighter.position)


## Each side's team's max HP by slot, [[side A's], [side B's]], for reading hit events.
func team_max_hp() -> Array:
	return teams.map(func(team: Array) -> Array: return team.map(func(f: Fighter) -> int: return f.max_hp))


## The move a projectile carries (its owner may be off the field since).
func projectile_move(projectile: Dictionary) -> BattleMove:
	return (teams[projectile.owner][projectile.slot] as Fighter).moves[projectile.move]


## Team members of `side` not knocked out, in team order.
func healthy(side: int) -> Array[Fighter]:
	var left: Array[Fighter] = []
	for fighter: Fighter in teams[side]:
		if not fighter.is_knocked_out():
			left.append(fighter)
	return left


## Whether the place `index` (index_of; a side in singles) is between Pokémon: its fighter is
## down and the next is on its way, or landing shielded. Meanwhile, in singles, the foe can only
## walk (frozen).
func is_waiting(index: int) -> bool:
	return _send_out_ticks[index] > 0 or (fighters[index].action == Fighter.Action.SEND_OUT and fighters[index].shielded)


## Whether `fighter` can only walk because its foe is between Pokémon. Only in singles: in
## doubles the others fight on through a send-out.
func frozen(fighter: Fighter) -> bool:
	return not doubles and is_waiting(1 - fighter.side)


## The index of a fighter out in `fighters`: place * 2 + side.
static func index_of(fighter: Fighter) -> int:
	return fighter.place * 2 + fighter.side


## The fighters out on `side` (in doubles a knocked-out one stays in its place until replaced).
func out(side: int) -> Array[Fighter]:
	var list: Array[Fighter] = []
	for index in range(side, fighters.size(), 2):
		list.append(fighters[index])
	return list


## `fighter`'s ally out in doubles (knocked out or not), else null.
func ally_of(fighter: Fighter) -> Fighter:
	return fighters[(1 - fighter.place) * 2 + fighter.side] if doubles else null


## Doubles: points each fighter out at its ally (Fighter.ally, for Friend Guard), after the
## start and every send-out.
func _link_allies() -> void:
	if not doubles:
		return
	for fighter in fighters:
		fighter.ally = ally_of(fighter)


## The fighter `fighter`'s single-target `move` would reach if aimed at `foe`: in doubles a foe
## whose ability draws moves of its type (Lightning Rod, Storm Drain), else `foe`.
func drawn_to(fighter: Fighter, foe: Fighter, move: BattleMove) -> Fighter:
	if not doubles or move.spread != "" or not move.is_projectile():
		return foe
	for other in out(1 - fighter.side):
		if other != foe and not other.is_knocked_out() and str(other.ability_effect.get("draws", "")) == move.type:
			return other
	return foe


## The foe `fighter` is aimed at: in singles the one foe out; in doubles a foe drawing attacks
## (Follow Me, Rage Powder, which Grass types and Overcoat ignore), else the foe in its target's
## place, or the other foe while that one is down (until a newcomer takes its place).
func target_of(fighter: Fighter) -> Fighter:
	if not doubles:
		return fighters[1 - fighter.side]
	var pull: Dictionary = _redirects[1 - fighter.side]
	if not pull.is_empty() and not (pull.powder and ("Grass" in fighter.types or fighter.ability == "overcoat")):
		return pull.fighter
	var locked := fighters[fighter.target_place * 2 + 1 - fighter.side]
	if not locked.is_knocked_out():
		return locked
	var other := fighters[(1 - fighter.target_place) * 2 + 1 - fighter.side]
	return other if not other.is_knocked_out() else locked


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
		saved.fighters[side].erase("ally_ai")
		saved.fighters[side].intents = intent_log[side]
		if doubles:
			saved.fighters[side].ally_intents = intent_log[side + 2]
	saved.checksum = checksum()
	return saved


## An intent in the compact form intent_log stores.
static func intent_to_log(intent: Dictionary) -> Array:
	var move: Vector2 = intent.get("move", Vector2.ZERO)
	var dodge: Vector2 = intent.get("dodge", Vector2.ZERO)
	var entry := [move.x, move.y, int(intent.get("use", -1)), dodge.x, dodge.y, int(intent.get("feint", -1)),
		1 if intent.get("guard", false) else 0, int(intent.get("switch", -1))]
	if intent.has("target"):
		entry.append(int(intent.target))
	return entry


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
	if entry.size() > 7 and int(entry[7]) >= 0:
		intent.switch = int(entry[7])
	if entry.size() > 8 and int(entry[8]) >= 0:
		intent.target = int(entry[8])
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
	for index in fighters.size():
		var intent: Dictionary = _controllers[index].decide(self, index)
		intents.append(intent)
		if record_intents:
			intent_log[index].append(intent_to_log(intent))
		# Between Pokémon after a knockout, a place's "switch" picks which comes out next.
		var side := index % 2
		var pick := int(intent.get("switch", -1))
		if _send_out_ticks[index] > 0 and pick >= 0 and pick < teams[side].size() and _on_bench(teams[side][pick]):
			_picks[index] = pick
	if tick == 0:
		_start_conditions()
	_tick_send_outs()
	# The sides take turns going first, alternating every tick.
	for i in fighters.size():
		var index := i if tick % 2 == 0 else i ^ 1
		_act(fighters[index], intents[index])
	_move_projectiles()
	if doubles:
		_tick_side_moves()
	if _drop_projectiles:
		_drop_projectiles = false
		projectiles.clear()
	if not _dropped_targets.is_empty():
		projectiles = projectiles.filter(func(projectile: Dictionary) -> bool:
			return not int(projectile.get("target", -1)) in _dropped_targets)
		_dropped_targets.clear()
	for ended in conditions.tick():
		if ended.has("screen"):
			_event("screen_end", int(ended.side), {"screen": ended.screen})
		elif ended.has("side_condition"):
			_event("side_condition_end", int(ended.side), {"condition": ended.side_condition})
		elif ended.has("field"):
			_event("field_end", -1, ended)
			if ended.field == "magicroom":
				_sync_items()
		else:
			_event("weather_end" if ended.has("weather") else "surge_end", -1, ended)
	if tick == overtime_tick:
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


func _act(fighter: Fighter, intent: Dictionary) -> void:
	if fighter.is_knocked_out():
		return
	var foe := target_of(fighter)
	for i in fighter.cooldowns.size():
		fighter.cooldowns[i] = maxi(0, fighter.cooldowns[i] - 1)
	fighter.feint_cooldown = maxi(0, fighter.feint_cooldown - 1)
	fighter.guard_cooldown = maxi(0, fighter.guard_cooldown - 1)
	fighter.helping_ticks = maxi(0, fighter.helping_ticks - 1)
	fighter.cheer_ticks = maxi(0, fighter.cheer_ticks - 1)
	if fighter.dodge_charges < Rules.DODGE_CHARGES:
		fighter.dodge_recharge_ticks += 1
		if fighter.dodge_recharge_ticks >= fighter.dodge_recharge_needed():
			fighter.dodge_charges += 1
			fighter.dodge_recharge_ticks = 0
	_tick_conditions(fighter)
	_tick_abilities(fighter, foe)
	_tick_item(fighter)
	_tick_weather(fighter)
	_tick_surge(fighter)
	if fighter.action == Fighter.Action.SEND_OUT:
		fighter.action_ticks -= 1
		if fighter.action_ticks <= 0:
			fighter.action = Fighter.Action.READY
			fighter.shielded = false
			_fevent("landed_out", fighter, {})
		return
	if frozen(fighter):
		intent = {"move": intent.get("move", Vector2.ZERO)}
	if fighter.is_knocked_out() or fighter.is_incapacitated():
		fighter.followups.clear()
		if not fighter.is_knocked_out():
			_drift(fighter, Vector2.ZERO)
		return
	# A fighter that could act may lock onto the other foe.
	var target := int(intent.get("target", -1))
	if doubles and (target == 0 or target == 1) and target != fighter.target_place and fighter.action == Fighter.Action.READY:
		fighter.target_place = target
		foe = target_of(fighter)
		_fevent("target", fighter, {"target_place": target})
	for followup in fighter.followups.duplicate():
		if not fighter.followups.has(followup):
			continue  # a parry dropped it
		followup.ticks -= 1
		if followup.ticks <= 0:
			fighter.followups.erase(followup)
			_strike(fighter, target_of(fighter), followup.move)
			if followup.last:
				_fevent("multi_hit_end", fighter, _aimed(target_of(fighter), {"move": fighter.moves[followup.move].id}))
	var to_foe := (foe.position - fighter.position).normalized()
	match fighter.action:
		Fighter.Action.DODGE:
			_slide(fighter, fighter.dodge_step)
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
				_slide(fighter, to_foe * minf(gap, Rules.MELEE_DASH_SPEED / Rules.TICK_RATE))
			else:
				_drift(fighter, Vector2.ZERO)
			fighter.action_ticks -= 1
			if fighter.feinting and fighter.action_ticks <= Rules.FEINT_BREAK_TICKS:
				fighter.feinting = false
				fighter.action = Fighter.Action.READY
				_fevent("feint_end", fighter, {"move": move.id})
			elif fighter.action_ticks <= 0:
				_release(fighter, foe)
		Fighter.Action.GUARD:
			_turn(fighter, to_foe, Rules.AIM_TURN_RATE)
			_drift(fighter, Vector2.ZERO)
			fighter.action_ticks -= 1
			if fighter.action_ticks == Rules.seconds_to_ticks(Rules.GUARD_RECOVERY):
				_fevent("guard_end", fighter, {"blocked": fighter.guard_blocked})
				if fighter.guard_blocked:
					fighter.action_ticks = 0
			if fighter.action_ticks <= 0:
				fighter.action = Fighter.Action.READY
		Fighter.Action.RECOVERY:
			_turn(fighter, to_foe, Rules.TURN_RATE)
			_drift(fighter, Vector2.ZERO)
			fighter.action_ticks -= 1
			if fighter.action_ticks <= 0:
				fighter.action = Fighter.Action.READY
		_:
			var dodge: Vector2 = intent.get("dodge", Vector2.ZERO)
			var use: int = intent.get("use", -1)
			var feint: int = intent.get("feint", -1)
			var guard: bool = intent.get("guard", false)
			if can_switch(index_of(fighter), int(intent.get("switch", -1))):
				_switch(fighter, teams[fighter.side][int(intent.switch)])
				return
			if dodge.length_squared() > 0.0 and fighter.can_dodge():
				fighter.dodge_charges -= 1
				fighter.action = Fighter.Action.DODGE
				fighter.action_ticks = Rules.seconds_to_ticks(Rules.DODGE_SECONDS)
				fighter.dodge_step = dodge.normalized() * Rules.DODGE_DISTANCE / fighter.action_ticks
				_fevent("dodge", fighter, {"direction": [dodge.normalized().x, dodge.normalized().y]})
			elif guard and fighter.can_guard():
				fighter.action = Fighter.Action.GUARD
				fighter.action_ticks = Rules.seconds_to_ticks(Rules.GUARD_SECONDS) + Rules.seconds_to_ticks(Rules.GUARD_RECOVERY)
				fighter.guard_cooldown = Rules.seconds_to_ticks(Rules.GUARD_COOLDOWN)
				fighter.guard_blocked = false
				_fevent("guard", fighter, {})
			elif fighter.move_ready(use) and _gap(fighter, foe) <= fighter.moves[use].reach():
				var move := fighter.moves[use]
				if fighter.confusion_ticks > 0 and _random.chance(Rules.CONFUSION_CHANCE):
					_hurt_in_confusion(fighter)
					return
				fighter.action = Fighter.Action.WINDUP
				fighter.action_ticks = conditions.windup_against(foe, move, fighter.windup_ticks(move))
				fighter.action_move = use
				fighter.cooldowns[use] = move.cooldown_ticks
				# Helping Hand boosts the next damaging move (every hit of it).
				fighter.helped = fighter.helping_ticks > 0 and move.is_damaging()
				if fighter.helped:
					fighter.helping_ticks = 0
				_fevent("windup", fighter, _aimed(foe, {"move": move.id}))
			elif fighter.can_feint(feint) and _gap(fighter, foe) <= fighter.moves[feint].reach():
				var move := fighter.moves[feint]
				fighter.action = Fighter.Action.WINDUP
				fighter.action_ticks = move.windup_ticks
				fighter.action_move = feint
				fighter.feinting = true
				fighter.feint_cooldown = Rules.seconds_to_ticks(Rules.FEINT_COOLDOWN)
				_fevent("feint", fighter, _aimed(foe, {"move": move.id, "ticks": move.windup_ticks - Rules.FEINT_BREAK_TICKS}))
			else:
				_walk(fighter, intent.get("move", Vector2.ZERO))
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


func _walk(fighter: Fighter, direction: Vector2) -> void:
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	_drift(fighter, direction * fighter.current_move_speed())


## Eases the fighter's velocity toward `target` (m/s) at Rules.ACCELERATION and moves it. The
## velocity kept is what it actually moved, so walls and the others' bodies stop it.
func _drift(fighter: Fighter, target: Vector2) -> void:
	var rate := Rules.ACCELERATION * fighter.current_agility()
	if fighter.glides and target.length_squared() < fighter.velocity.length_squared():
		rate *= Rules.GLIDE_BRAKING
	fighter.velocity = fighter.velocity.move_toward(target, rate / Rules.TICK_RATE)
	var before := fighter.position
	_slide(fighter, fighter.velocity / Rules.TICK_RATE)
	fighter.velocity = (fighter.position - before) * Rules.TICK_RATE


## Turns the fighter's facing toward `direction` by at most `degrees_per_second` this tick.
static func _turn(fighter: Fighter, direction: Vector2, degrees_per_second: float) -> void:
	if direction.length_squared() < 1e-8:
		return
	var step := deg_to_rad(degrees_per_second * fighter.current_agility()) / Rules.TICK_RATE
	fighter.facing = fighter.facing.rotated(clampf(fighter.facing.angle_to(direction), -step, step)).normalized()


## Moves a fighter by `delta`, kept inside the arena wall and outside the other fighters'
## hitboxes (it slides around them instead of passing through).
func _slide(fighter: Fighter, delta: Vector2) -> void:
	var next := fighter.position + delta
	for other in fighters:
		# A fainted fighter whose next Pokémon is on its way (or, in doubles, any fainted one) is
		# no obstacle.
		if other == fighter or (other.is_knocked_out() and (doubles or _send_out_ticks[index_of(other)] > 0)):
			continue
		var contact := fighter.radius + other.radius
		var away := next - other.position
		if away.length() < contact:
			if away.length_squared() < 1e-8:
				away = fighter.position - other.position
			next = other.position + away.normalized() * contact
	var limit := Rules.ARENA_RADIUS - fighter.radius
	if next.length() > limit:
		next = next.normalized() * limit
	next = terrain.push_out(next, fighter.radius, fighter.ground, fighter.step_height())
	if next.length() > limit:
		next = next.normalized() * limit
	fighter.position = next
	fighter.ground = terrain.height_at(next)


func _release(fighter: Fighter, foe: Fighter) -> void:
	var move := fighter.moves[fighter.action_move]
	fighter.action = Fighter.Action.RECOVERY
	fighter.action_ticks = move.recovery_ticks
	if move.is_self():
		if not move.field_effect.is_empty():
			_field_move(fighter, move)
		elif move.kind == BattleMove.Kind.HEAL and move.team_heal:
			_team_heal(fighter, move)
		elif move.kind == BattleMove.Kind.HEAL:
			_heal(fighter, roundi(fighter.max_hp * conditions.heal_share(fighter, move)), move.id)
		elif move.kind == BattleMove.Kind.ALLY:
			_support(fighter, move)
		elif move.kind == BattleMove.Kind.REDIRECT:
			_draw_attacks(fighter, move)
		elif move.kind == BattleMove.Kind.ARENA and move.wide_guard:
			if doubles:
				_wide_guard[fighter.side] = Rules.seconds_to_ticks(Rules.WIDE_GUARD_SECONDS)
				_fevent("wide_guard", fighter, {"move": move.id})
			else:
				_fevent("failed", fighter, {"move": move.id})
		elif move.kind == BattleMove.Kind.ARENA and not move.hazard.is_empty():
			_lay_hazard(fighter, move)
		elif move.kind == BattleMove.Kind.ARENA and move.clears == "both":
			_clear_hazards(fighter, move, true)
		elif move.kind == BattleMove.Kind.ARENA and not move.screen.is_empty():
			var ticks := ArenaConditions.screen_ticks_for(fighter)
			conditions.set_screen(fighter.side, move.screen, ticks)
			_fevent("screen", fighter, {"screen": move.screen, "move": move.id, "seconds": ticks / float(Rules.TICK_RATE)})
		elif move.kind == BattleMove.Kind.ARENA and not move.surge.is_empty():
			_set_surge(fighter, move.surge, {"move": move.id})
		elif move.kind == BattleMove.Kind.ARENA:
			_set_weather(fighter, move.weather, {"move": move.id})
		else:
			_boost(fighter, move.boosts, move.id)
			if move.clears == "both":
				_clear_hazards(fighter, move, false)
	else:
		var hits := _roll_hits(fighter, move)
		var parried := _strike(fighter, foe, fighter.action_move)
		var interval := Rules.seconds_to_ticks(Rules.MULTI_HIT_INTERVAL)
		for i in range(1, hits if not parried else 1):
			fighter.followups.append({"ticks": i * interval, "move": fighter.action_move, "last": i == hits - 1})
		if move.recharges:
			_fevent("recharge", fighter, {"move": move.id})
		if move.self_destructs:
			_hurt(fighter, fighter.hp, "self_destruct", {"move": move.id})


## One strike of a damaging move, or the launch of a projectile. Returns whether the foe
## parried it.
func _strike(fighter: Fighter, foe: Fighter, move_index: int) -> bool:
	var move := fighter.moves[move_index]
	if doubles and move.kind == BattleMove.Kind.AREA:
		_strike_area(fighter, move)
		return false
	match move.kind:
		BattleMove.Kind.MELEE, BattleMove.Kind.AREA:
			var reach := Rules.MELEE_REACH if move.kind == BattleMove.Kind.MELEE else Rules.AREA_RADIUS
			if move.kind == BattleMove.Kind.AREA:
				_fevent("blast", fighter, {"move": move.id})
			var reach_up := Rules.MELEE_HEIGHT if move.kind == BattleMove.Kind.MELEE else Rules.AREA_HEIGHT
			if _gap(fighter, foe) > reach or foe.is_knocked_out() or absf(foe.ground - fighter.ground) > reach_up:
				_fevent("miss", fighter, _aimed(foe, {"move": move.id}))
			elif foe.is_invulnerable():
				_fevent("miss", fighter, _aimed(foe, {"move": move.id}))
				_fevent("dodged", foe, {"move": move.id})
			elif foe.guards_against(fighter.position - foe.position):
				_guarded(fighter, foe, move)
				return move.kind == BattleMove.Kind.MELEE
			else:
				_hit(fighter, foe, move)
		_:
			var drawn := drawn_to(fighter, foe, move)
			if drawn != foe:
				_ability_event(drawn)
				_fire(fighter, drawn, move_index, (drawn.position - fighter.position).normalized())
				return false
			_fire(fighter, foe, move_index, fighter.facing)
			# A spread status or debuff move fires at the other foe too, if it's in range and sight.
			var other := _other_foe(fighter, foe)
			if move.spread == "foes" and not move.is_damaging() and other != null and _gap(fighter, other) <= move.reach() \
					and can_see(fighter, other):
				_fire(fighter, other, move_index, (other.position - fighter.position).normalized())
	return false


## The foe out other than `foe` in doubles, if it's up; else null.
func _other_foe(fighter: Fighter, foe: Fighter) -> Fighter:
	if not doubles:
		return null
	for other in out(1 - fighter.side):
		if other != foe and not other.is_knocked_out():
			return other
	return null


## Launches `fighter`'s move `move_index` at `foe` along `direction`.
func _fire(fighter: Fighter, foe: Fighter, move_index: int, direction: Vector2) -> void:
	var move := fighter.moves[move_index]
	_projectile_count += 1
	# Aimed along the facing, rising or falling to reach the foe's chest at its distance.
	var start := fighter.position + direction * fighter.radius
	var speed := conditions.projectile_speed(fighter, move) / Rules.TICK_RATE
	if move.physical:
		speed *= float(fighter.ability_effect.get("physical_projectile_speed", 1.0))
	var ticks_to_foe := maxf(start.distance_to(foe.position) / speed, 1.0)
	var projectile := {
		"id": _projectile_count,
		"owner": fighter.side,
		"slot": fighter.slot,
		"move": move_index,
		"position": start,
		"velocity": direction * speed,
		"height": fighter.ground + Rules.CHEST_HEIGHT,
		"rise": (foe.ground - fighter.ground) / ticks_to_foe,
		"travelled": 0.0,
	}
	if doubles:
		projectile.target = index_of(foe)
	projectiles.append(projectile)
	_fevent("fire", fighter, _aimed(foe, {"move": move.id}))


## An ALLY move (doubles): boosts or a boon for the ally (and the user, for Howl). Without an
## ally up it fails.
func _support(fighter: Fighter, move: BattleMove) -> void:
	var helped: Array[Fighter] = []
	if move.with_user:
		helped.append(fighter)
	var ally := ally_of(fighter)
	if ally != null and not ally.is_knocked_out():
		helped.append(ally)
	if helped.is_empty() or (helped == [fighter] and move.ally_effect != ""):
		_fevent("failed", fighter, {"move": move.id})
		return
	for target in helped:
		if target != fighter:
			_fevent("support", fighter, _aimed(target, {"move": move.id, "effect": move.ally_effect}))
		if not move.boosts.is_empty():
			_boost(target, move.boosts, move.id)
		match move.ally_effect:
			"helping":
				target.helping_ticks = Rules.seconds_to_ticks(Rules.HELPING_HAND_SECONDS)
			"cheer":
				target.cheer_ticks = Rules.seconds_to_ticks(Rules.CHEER_SECONDS)


## A field or side condition's move (§9.11), or Haze or Court Change. A room used while it's up
## ends it; Gravity, Tailwind, Safeguard and Mist fail while they're up.
func _field_move(fighter: Fighter, move: BattleMove) -> void:
	var name := move.field_effect
	if name == "haze":
		for other in fighters:
			if not other.is_knocked_out():
				for stat: String in other.boosts:
					other.boosts[stat] = 0
				other.stage_ticks = 0
		_fevent("haze", fighter, {"move": move.id})
	elif name == "courtchange":
		conditions.screens.reverse()
		conditions.hazards.reverse()
		conditions.sides.reverse()
		_fevent("court_change", fighter, {"move": move.id})
	elif name in ArenaConditions.SIDE_CONDITIONS:
		if conditions.sides[fighter.side].has(name):
			_fevent("failed", fighter, {"move": move.id})
			return
		var ticks := ArenaConditions.field_ticks(name)
		conditions.sides[fighter.side][name] = ticks
		_fevent("side_condition", fighter, {"condition": name, "move": move.id, "seconds": ticks / float(Rules.TICK_RATE)})
	elif conditions.field.has(name):
		if name == "gravity":
			_fevent("failed", fighter, {"move": move.id})
			return
		conditions.field.erase(name)
		_fevent("field_end", fighter, {"field": name, "move": move.id})
	else:
		var ticks := ArenaConditions.field_ticks(name)
		conditions.field[name] = ticks
		_fevent("field", fighter, {"field": name, "move": move.id, "seconds": ticks / float(Rules.TICK_RATE)})
	if name == "magicroom":
		_sync_items()


## Magic Room turns every held item off while it's up (one-use items stay spent).
func _sync_items() -> void:
	var off := conditions.has_field("magicroom")
	for team: Array in teams:
		for member: Fighter in team:
			member.item_effect = {} if off else Items.effect(member.item)


## A team heal: the user and its ally up each heal their share, and with Jungle Healing or Lunar
## Blessing lose their status condition.
func _team_heal(fighter: Fighter, move: BattleMove) -> void:
	var healed: Array[Fighter] = [fighter]
	var ally := ally_of(fighter)
	if ally != null and not ally.is_knocked_out():
		healed.append(ally)
	for target in healed:
		_heal(target, roundi(target.max_hp * conditions.heal_share(target, move)), move.id)
		if move.cures and not target.status.is_empty():
			_end_status(target)


## Follow Me and Rage Powder: in doubles every foe's attacks go for the user for a while.
func _draw_attacks(fighter: Fighter, move: BattleMove) -> void:
	if not doubles:
		_fevent("failed", fighter, {"move": move.id})
		return
	_redirects[fighter.side] = {"fighter": fighter, "ticks": Rules.seconds_to_ticks(Rules.REDIRECT_SECONDS),
		"powder": move.flags.has("powder")}
	_fevent("redirect", fighter, {"move": move.id})


## Doubles' side moves running down: a pull ends with its time or its fighter (knocked out or
## recalled), Wide Guard with its time.
func _tick_side_moves() -> void:
	for side in 2:
		_wide_guard[side] = maxi(0, _wide_guard[side] - 1)
		var pull := _redirects[side]
		if pull.is_empty():
			continue
		pull.ticks -= 1
		var fighter: Fighter = pull.fighter
		if pull.ticks <= 0 or fighter.is_knocked_out() or not fighters.has(fighter):
			_redirects[side] = {}
			_fevent("redirect_end", fighter, {})


## Whether Wide Guard is up on `side` (doubles).
func wide_guarded(side: int) -> bool:
	return doubles and _wide_guard[side] > 0


## A spread (area) move going off in doubles: it hits every foe in its ring, and the ally too for
## "all" moves, at Rules.SPREAD_FACTOR each when it hits more than one.
func _strike_area(fighter: Fighter, move: BattleMove) -> void:
	_fevent("blast", fighter, {"move": move.id})
	var reached: Array[Fighter] = []
	for other in fighters:
		if other == fighter or other.is_knocked_out() or (other.side == fighter.side and move.spread != "all"):
			continue
		if _gap(fighter, other) <= Rules.AREA_RADIUS and absf(other.ground - fighter.ground) <= Rules.AREA_HEIGHT:
			# Telepathy: the ally's moves pass it by.
			if other.side == fighter.side and other.ability_effect.get("ally_immune", false):
				_ability_event(other)
				continue
			reached.append(other)
	if reached.is_empty():
		_fevent("miss", fighter, {"move": move.id})
		return
	var factor := Rules.SPREAD_FACTOR if reached.size() > 1 else 1.0
	for other in reached:
		if other.is_knocked_out():
			continue
		if other.is_invulnerable():
			_fevent("miss", fighter, {"move": move.id})
			_fevent("dodged", other, {"move": move.id})
		elif wide_guarded(other.side):
			_fevent("miss", fighter, _aimed(other, {"move": move.id}))
			_fevent("wide_guarded", other, {"move": move.id})
		elif other.guards_against(fighter.position - other.position):
			_guarded(fighter, other, move)
		else:
			_hit(fighter, other, move, factor)


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
		var owner: Fighter = teams[projectile.owner][projectile.slot]
		var target := fighters[int(projectile.target)] if doubles else fighters[1 - projectile.owner]
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
			if move.spread != "" and wide_guarded(target.side):
				_fevent("miss", owner, _aimed(target, {"move": move.id}))
				_fevent("wide_guarded", target, {"move": move.id})
				continue
			if not target.is_invulnerable():
				if move.is_damaging():
					_hit(owner, target, move)
				else:
					_land(owner, target, move)
				continue
			if not projectile.get("dodged", false):
				projectile.dodged = true  # it flies on through the dodging fighter
				_fevent("dodged", target, {"move": move.id})
		projectile.position = end
		projectile.height = height + float(projectile.rise)
		projectile.travelled += (projectile.velocity as Vector2).length()
		if terrain.height_at(end) > projectile.height:
			_fevent("blocked", owner, {"move": move.id, "position": [end.x, end.y], "height": projectile.height})
			_fevent("miss", owner, {"move": move.id})
		elif projectile.travelled < Rules.PROJECTILE_RANGE * 1.5 and end.length() < Rules.ARENA_RADIUS:
			remaining.append(projectile)
		else:
			_fevent("miss", owner, {"move": move.id})
	projectiles = remaining


## `spread` is Rules.SPREAD_FACTOR for a spread move hitting several fighters at once, else 1.
func _hit(attacker: Fighter, defender: Fighter, move: BattleMove, spread := 1.0) -> void:
	if move.id in ArenaConditions.SCREEN_BREAKERS:
		for screen: String in conditions.screens[defender.side].keys():
			conditions.screens[defender.side].erase(screen)
			_fevent("screen_end", defender, {"screen": screen, "shattered": true})
	var outcome := damage(attacker, defender, move, _data, _random)
	if spread < 1.0:
		outcome.damage = maxi(1, floori(outcome.damage * spread))
	outcome.damage = maxi(1, floori(outcome.damage * Rules.overtime_factor(tick, overtime_tick / float(Rules.TICK_RATE))))
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
	_fevent("hit", attacker, {"move": move.id, "damage": dealt if holds or sash else outcome.damage, "crit": outcome.crit,
		"effectiveness": outcome.effectiveness, "hp": defender.hp, "slot": attacker.slot, "target_side": defender.side,
		"target_slot": defender.slot})
	if holds:
		_ability_event(defender)
	if sash:
		_item_event(defender)
	if immune and Abilities.absorbs(defender, move):
		_absorb(defender, move)
	_ability_on_hit(attacker, defender, move)
	_item_on_hit(attacker, defender, move, dealt)
	if defender.is_knocked_out():
		_knocked_out(defender)
	else:
		var push := (defender.position - attacker.position).normalized()
		defender.velocity += push * Rules.knockback_speed(float(dealt) / defender.max_hp, defender.weight_kg)
		if defender.action == Fighter.Action.WINDUP and defender.moves[defender.action_move].kind == BattleMove.Kind.HEAL:
			defender.action = Fighter.Action.READY
			defender.action_ticks = 0
			_fevent("interrupt", defender, {"move": defender.moves[defender.action_move].id})
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
	if move.clears == "own" and not attacker.is_knocked_out() and not conditions.hazards[attacker.side].is_empty():
		_clear_side(attacker.side, move.id)


## A hit stopped by the defender's guard: no damage or effects. Parrying a melee strike
## staggers the attacker and drops its remaining multi-hit strikes.
func _guarded(attacker: Fighter, defender: Fighter, move: BattleMove) -> void:
	defender.guard_blocked = true
	var parry := move.kind == BattleMove.Kind.MELEE
	_fevent("miss", attacker, _aimed(defender, {"move": move.id}))
	_fevent("guarded", defender, _aimed(attacker, {"move": move.id, "parry": parry}))
	if parry:
		attacker.followups.clear()
		if attacker.action == Fighter.Action.READY or attacker.action == Fighter.Action.RECOVERY:
			attacker.action = Fighter.Action.RECOVERY
			attacker.action_ticks = maxi(attacker.action_ticks, Rules.seconds_to_ticks(Rules.PARRY_STAGGER))


## Reports that `fighter`'s ability took effect, so the view can name it.
func _ability_event(fighter: Fighter, details := {}) -> void:
	details.merge({"ability": fighter.ability, "name": Abilities.display_name(fighter.ability)})
	_fevent("ability", fighter, details)


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
	_fevent("item", fighter, details)


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
		_fevent("status_end", fighter, {"status": "confusion"})


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
	if entry.get("intimidate", false) and not is_waiting(index_of(foe)):
		fighter.intimidate_ticks -= 1
		if fighter.intimidate_ticks <= 0:
			fighter.intimidate_ticks = Rules.seconds_to_ticks(Abilities.INTIMIDATE_SECONDS)
			_ability_event(fighter)
			# In doubles it reaches both foes up.
			var scared: Array[Fighter] = [foe]
			if doubles:
				scared = []
				for other in out(1 - fighter.side):
					if not other.is_knocked_out() and not is_waiting(index_of(other)):
						scared.append(other)
			for other in scared:
				if other.ability_effect.get("intimidate_immune", false):
					_ability_event(other)
				else:
					_boost(other, {"atk": -1}, fighter.ability, fighter)
	var speed_boost: Dictionary = entry.get("speed_boost", {})
	if not speed_boost.is_empty():
		fighter.speed_boost_ticks += 1
		if fighter.speed_boost_ticks >= Rules.seconds_to_ticks(float(speed_boost.seconds)):
			fighter.speed_boost_ticks = 0
			if fighter.boosts.spe < int(speed_boost.max):
				_ability_event(fighter)
				_boost(fighter, {"spe": 1}, fighter.ability)


## Sends out each place's next Pokémon once its lull after a knockout is over.
func _tick_send_outs() -> void:
	for side in 2:
		_switch_cooldown[side] = maxi(0, _switch_cooldown[side] - 1)
	for index in fighters.size():
		if _send_out_ticks[index] > 0:
			_send_out_ticks[index] -= 1
			if _send_out_ticks[index] == 0:
				var side := index % 2
				var picked := _picks[index]
				var slot := picked if picked >= 0 and _on_bench(teams[side][picked]) else next_up(side)
				_picks[index] = -1
				if slot >= 0:
					_send_out(teams[side][slot], true, index / 2)


## Whether a team member is healthy and on the bench, so it could be sent out.
func _on_bench(member: Fighter) -> bool:
	return not member.is_knocked_out() and not fighters.has(member)


## Whether the fighter out at `index` (index_of; a side in singles) can switch for team member
## `slot` now: it could act, its side's switch cooldown is over, the member is healthy and on the
## bench, and (in singles) the foe isn't between Pokémon.
func can_switch(index: int, slot: int) -> bool:
	var fighter := fighters[index]
	var team: Array = teams[fighter.side]
	return slot >= 0 and slot < team.size() and _switch_cooldown[fighter.side] == 0 and _on_bench(team[slot]) \
		and fighter.can_act() and not frozen(fighter)


## Ticks until `side` can switch again.
func switch_cooldown(side: int) -> int:
	return _switch_cooldown[side]


## Recalls `fighter` for `incoming`, which lands where it stood, open to hits, over
## Rules.SWITCH_SECONDS. Stat stages, confusion and the like clear on the way out; HP, major
## status and move cooldowns stay with the Pokémon, frozen on the bench, and bad poison starts
## over.
func _switch(fighter: Fighter, incoming: Fighter) -> void:
	_fevent("recall", fighter, {"species": fighter.species_id})
	incoming.position = fighter.position
	incoming.facing = fighter.facing
	incoming.ground = fighter.ground
	incoming.velocity = Vector2.ZERO
	incoming.target_place = fighter.target_place
	_leave(fighter)
	incoming.place = fighter.place
	fighters[index_of(fighter)] = incoming
	if doubles or not fighters[1 - fighter.side].is_knocked_out():
		_slide(incoming, Vector2.ZERO)
	_send_out(incoming, false, fighter.place)


## Whether `fighter` is on the bench: frozen, so effects of its own projectiles still in flight
## (recoil, drain, Life Orb) and of the foe's abilities don't reach it.
func _benched(fighter: Fighter) -> bool:
	return not fighters.has(fighter)


## What a fighter loses when it's recalled.
static func _leave(fighter: Fighter) -> void:
	for stat: String in fighter.boosts:
		fighter.boosts[stat] = 0
	fighter.stage_ticks = 0
	fighter.confusion_ticks = 0
	fighter.toxic_level = 0
	fighter.stun_ticks = 0
	fighter.followups.clear()
	fighter.velocity = Vector2.ZERO
	fighter.action = Fighter.Action.READY
	fighter.action_ticks = 0
	fighter.feinting = false
	fighter.flash_fire_ticks = 0
	fighter.intimidate_ticks = 0
	fighter.speed_boost_ticks = 0
	fighter.weak_armor_ticks = 0
	fighter.helping_ticks = 0
	fighter.cheer_ticks = 0
	fighter.helped = false


## The team slot `side` sends out next: its first member healthy and on the bench, or -1.
func next_up(side: int) -> int:
	for member: Fighter in teams[side]:
		if _on_bench(member):
			return member.slot
	return -1


## `fighter` comes out. After a knockout (`after_knockout`) it lands at its side's start spot
## (pushed clear of the foe), shielded, and projectiles in flight vanish; on a switch it lands
## where it was put, open to hits. Either way the side's switch cooldown starts. Abilities that
## act on entry (weather and surge setters) do; Intimidate strikes on its first tick.
func _send_out(fighter: Fighter, after_knockout := true, place := 0) -> void:
	fighter.place = place
	fighters[index_of(fighter)] = fighter
	if after_knockout:
		_start_stretch(tick)
		fighter.target_place = place
		_place_at_start(fighter)
		var foe := target_of(fighter)
		if not foe.is_knocked_out():
			_slide(fighter, Vector2.ZERO)
			var to_foe := foe.position - fighter.position
			if to_foe.length_squared() > 1e-8:
				fighter.facing = to_foe.normalized()
		elif doubles:
			_slide(fighter, Vector2.ZERO)
		if not doubles:
			projectiles.clear()
	fighter.action = Fighter.Action.SEND_OUT
	fighter.action_ticks = Rules.seconds_to_ticks(Rules.SEND_OUT_SECONDS if after_knockout else Rules.SWITCH_SECONDS)
	fighter.shielded = after_knockout
	_link_allies()
	_switch_cooldown[fighter.side] = Rules.seconds_to_ticks(Rules.SWITCH_COOLDOWN_SECONDS)
	_fevent("send_out", fighter, {"species": fighter.species_id, "switch": not after_knockout})
	_count_benches()
	_entry_hazards(fighter)
	var weather := Abilities.sets_weather(fighter)
	var surge := Abilities.sets_surge(fighter)
	if not weather.is_empty() or not surge.is_empty():
		_ability_event(fighter)
		if not weather.is_empty():
			_set_weather(fighter, weather, {"ability": fighter.ability})
		else:
			_set_surge(fighter, surge, {"ability": fighter.ability})


## Keeps the arena conditions' count of each side's healthy bench, for valuing hazards.
func _count_benches() -> void:
	for side in 2:
		var count := 0
		for member: Fighter in teams[side]:
			if _on_bench(member):
				count += 1
		conditions.bench[side] = count


## Lays a layer of `move`'s hazard on the foe's side, if it has room for one.
func _lay_hazard(fighter: Fighter, move: BattleMove) -> void:
	var side := 1 - fighter.side
	var layers := int(conditions.hazards[side].get(move.hazard, 0))
	if layers >= int(ArenaConditions.HAZARDS[move.hazard]):
		_fevent("hazard_failed", fighter, {"hazard": move.hazard, "move": move.id})
		return
	conditions.hazards[side][move.hazard] = layers + 1
	_fevent("hazard", fighter, {"hazard": move.hazard, "layers": layers + 1, "target_side": side, "move": move.id})


## Defog and Tidy Up: every hazard on both sides goes, and with Defog (`screens`) the foe's
## screens.
func _clear_hazards(fighter: Fighter, move: BattleMove, screens: bool) -> void:
	for side in 2:
		if not conditions.hazards[side].is_empty():
			_clear_side(side, move.id)
	if screens:
		var foe_side := 1 - fighter.side
		for screen: String in conditions.screens[foe_side].keys():
			conditions.screens[foe_side].erase(screen)
			_event("screen_end", foe_side, {"screen": screen, "cleared": true})


func _clear_side(side: int, move_id: String) -> void:
	_event("hazards_cleared", side, {"hazards": conditions.hazards[side].keys(), "move": move_id})
	conditions.hazards[side] = {}


## The hazards on `fighter`'s side acting as it comes out (§9.11).
func _entry_hazards(fighter: Fighter) -> void:
	var laid: Dictionary = conditions.hazards[fighter.side]
	if laid.is_empty():
		return
	var grounded := ArenaConditions.grounded(fighter)
	var guarded := Abilities.magic_guard(fighter)
	if laid.has("stealthrock") and not guarded:
		var effectiveness := Rules.compressed_effectiveness(_data.effectiveness("Rock", fighter.types))
		_hurt(fighter, maxi(1, roundi(fighter.max_hp * ArenaConditions.ROCK_SHARE * effectiveness)), "hazard_damage",
			{"hazard": "stealthrock"})
	if laid.has("spikes") and grounded and not guarded and not fighter.is_knocked_out():
		_hurt(fighter, maxi(1, roundi(fighter.max_hp * ArenaConditions.SPIKES_SHARES[int(laid.spikes)])), "hazard_damage",
			{"hazard": "spikes"})
	if laid.has("toxicspikes") and grounded and not fighter.is_knocked_out():
		if "Poison" in fighter.types:
			laid.erase("toxicspikes")
			_fevent("hazards_cleared", fighter, {"hazards": ["toxicspikes"], "absorbed": true})
		else:
			_inflict(fighter, "tox" if int(laid.toxicspikes) > 1 else "psn")
	if laid.has("stickyweb") and grounded and not fighter.is_knocked_out():
		_fevent("hazard_hit", fighter, {"hazard": "stickyweb"})
		_boost(fighter, {"spe": -1}, "stickyweb", target_of(fighter))


## A fighter fainting: with more of its team to come, its side sends out the next after a lull,
## and every projectile in flight vanishes (in doubles only those aimed at it, and a place is
## refilled only while the bench has someone not already on the way to the other).
func _knocked_out(fighter: Fighter) -> void:
	var left := healthy(fighter.side).size()
	_count_benches()
	_fevent("knockout", fighter, {"left": left})
	if doubles:
		fighter.followups.clear()
		_dropped_targets.append(index_of(fighter))
		var coming := 0
		for other in out(fighter.side):
			if _send_out_ticks[index_of(other)] > 0:
				coming += 1
		if conditions.bench[fighter.side] > coming:
			_send_out_ticks[index_of(fighter)] = Rules.seconds_to_ticks(Rules.KNOCKOUT_LULL_SECONDS)
	elif left > 0:
		_send_out_ticks[fighter.side] = Rules.seconds_to_ticks(Rules.KNOCKOUT_LULL_SECONDS)
		_drop_projectiles = true
		fighter.followups.clear()


## The conditions a battle starts with, on its first tick: the arena's or spec's weather, then
## weather- and surge-setting abilities, the faster fighter's first, so the slower one's wins
## (a tie goes to the battle's random stream).
func _start_conditions() -> void:
	if not conditions.weather.is_empty():
		_event("weather", -1, {"weather": conditions.weather, "seconds": -1})
	var setters: Array[Fighter] = []
	for fighter in fighters:
		if not Abilities.sets_weather(fighter).is_empty() or not Abilities.sets_surge(fighter).is_empty():
			setters.append(fighter)
	if setters.size() == 2:
		var a_speed := setters[0].stat("spe")
		var b_speed := setters[1].stat("spe")
		if a_speed < b_speed or (a_speed == b_speed and _random.chance(0.5)):
			setters.reverse()
	elif setters.size() > 2:
		# Fastest first (a tie keeps the order out), so the slowest one's goes last and wins.
		setters.sort_custom(func(a: Fighter, b: Fighter) -> bool:
			return a.stat("spe") > b.stat("spe") or (a.stat("spe") == b.stat("spe") and index_of(a) < index_of(b)))
	for fighter in setters:
		_ability_event(fighter)
		if not Abilities.sets_weather(fighter).is_empty():
			_set_weather(fighter, Abilities.sets_weather(fighter), {"ability": fighter.ability})
		else:
			_set_surge(fighter, Abilities.sets_surge(fighter), {"ability": fighter.ability})


## Sets a weather from `setter`'s move or ability (`source`: {"move"} or {"ability"}), for its
## usual time or longer with the matching rock.
func _set_weather(setter: Fighter, weather: String, source: Dictionary) -> void:
	var ticks := ArenaConditions.weather_ticks_for(setter, weather)
	var renewed := conditions.weather == weather
	# Renewing never shortens a weather: a battle-long one stays, a longer one keeps its time.
	if renewed and (conditions.weather_ticks < 0 or conditions.weather_ticks > ticks):
		ticks = conditions.weather_ticks
	conditions.set_weather(weather, ticks)
	var details := {"weather": weather, "seconds": -1.0 if ticks < 0 else ticks / float(Rules.TICK_RATE), "renewed": renewed}
	details.merge(source)
	_fevent("weather", setter, details)


## Sets a surge from `setter`'s move or ability (`source`), for its usual time or longer with a
## Terrain Extender.
func _set_surge(setter: Fighter, surge: String, source: Dictionary) -> void:
	var ticks := ArenaConditions.surge_ticks_for(setter)
	var renewed := conditions.surge == surge
	conditions.set_surge(surge, ticks)
	var details := {"surge": surge, "seconds": ticks / float(Rules.TICK_RATE), "renewed": renewed}
	details.merge(source)
	_fevent("surge", setter, details)


## Grassy ground healing a grounded fighter, once a second.
func _tick_surge(fighter: Fighter) -> void:
	if tick % Rules.TICK_RATE == 0 and conditions.surge_for(fighter) == "grassy" and not fighter.is_knocked_out():
		_heal(fighter, maxi(1, roundi(fighter.max_hp * ArenaConditions.GRASSY_HEAL)), "grassyterrain", "regen")


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
	_fevent("landed", attacker, _aimed(defender, {"move": move.id}))
	_apply_effect(attacker, defender, {"boosts": move.boosts, "status": move.status, "confuses": move.confuses}, move.id)


func _apply_effect(attacker: Fighter, defender: Fighter, effect: Dictionary, move_id: String) -> void:
	if not str(effect.get("status", "")).is_empty():
		_inflict(defender, effect.status, attacker)
	if effect.get("confuses", false) and defender.confusion_ticks == 0:
		if Abilities.status_immune(defender, "confusion"):
			_ability_event(defender)
		elif not conditions.blocks_status(defender, "confusion"):
			defender.confusion_ticks = Rules.seconds_to_ticks(Rules.CONFUSION_SECONDS)
			_fevent("status", defender, {"status": "confusion"})
			_check_lum(defender)
	if not effect.get("boosts", {}).is_empty():
		_boost(defender, effect.boosts, move_id, attacker)
	if not effect.get("self_boosts", {}).is_empty():
		_boost(attacker, effect.self_boosts, move_id)


## Gives a major status unless the fighter already has one or its type or ability is immune.
## `source` is the foe that caused it, if any (Synchronize passes it back).
func _inflict(fighter: Fighter, status: String, source: Fighter = null) -> void:
	if not fighter.status.is_empty() or fighter.is_knocked_out() or _benched(fighter):
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
	_fevent("status", fighter, {"status": status})
	_check_lum(fighter)
	if source != null and fighter.ability_effect.get("synchronize", false) and status in ["brn", "par", "psn", "tox"]:
		_ability_event(fighter)
		_inflict(source, status)


func _end_status(fighter: Fighter) -> void:
	_fevent("status_end", fighter, {"status": fighter.status})
	fighter.status = ""
	fighter.status_ticks = 0


## Changes stat stages within +-6 and reports the changes that took effect. `foe` is the foe
## making the change, if any: abilities can block its drops (Clear Body) or answer them
## (Defiant).
func _boost(fighter: Fighter, changes: Dictionary, move_id: String, foe: Fighter = null) -> void:
	if _benched(fighter):
		return
	if foe != null:
		var allowed := Abilities.allowed_drops(fighter, changes)
		if allowed.size() < changes.size():
			_ability_event(fighter)
		changes = allowed
		if conditions.misted(fighter):
			var kept := {}
			for stat: String in changes:
				if int(changes[stat]) > 0:
					kept[stat] = changes[stat]
			if kept.size() < changes.size():
				_fevent("mist_blocked", fighter, {"move": move_id})
			changes = kept
	var applied := {}
	for stat: String in changes:
		var before: int = fighter.boosts[stat]
		fighter.boosts[stat] = clampi(before + int(changes[stat]), -Rules.MAX_STAGE, Rules.MAX_STAGE)
		if fighter.boosts[stat] != before:
			applied[stat] = fighter.boosts[stat] - before
	if not applied.is_empty():
		fighter.stage_ticks = 0
		_fevent("boost", fighter, {"boosts": applied, "move": move_id})
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
		_fevent("stage_decay", fighter, {"boosts": applied})


## Restores HP, reported as `type`: "heal", or "regen" for the small steady healing of
## items like Leftovers, which the view doesn't call out.
func _heal(fighter: Fighter, amount: int, move_id: String, type := "heal") -> void:
	if _benched(fighter):
		return
	var healed := mini(amount, fighter.max_hp - fighter.hp)
	if healed > 0:
		fighter.hp += healed
		_fevent(type, fighter, {"amount": healed, "hp": fighter.hp, "move": move_id})


## Takes HP outside a hit (status damage, recoil, confusion), reporting it as `type`.
func _hurt(fighter: Fighter, amount: int, type: String, details: Dictionary) -> void:
	if fighter.is_knocked_out() or _benched(fighter):
		return
	fighter.hp = maxi(0, fighter.hp - amount)
	details.merge({"damage": amount, "hp": fighter.hp})
	_fevent(type, fighter, details)
	if fighter.is_knocked_out():
		_knocked_out(fighter)
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
			_fevent("status_end", fighter, {"status": "confusion"})
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
					_fevent("stunned", fighter, {})
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
	var crit := random.chance(Rules.CHEER_CRIT_CHANCE if attacker.cheer_ticks > 0 else Rules.CRIT_CHANCE)
	var roll := random.range_float(Rules.ROLL_MIN, Rules.ROLL_MAX)
	# Critical hits get through screens.
	var total: float = parts.base * parts.factor * (Rules.CRIT_MULTIPLIER if crit else parts.screen) * roll
	return {"damage": maxi(1, floori(total)), "crit": crit, "effectiveness": parts.effectiveness}


## A hit's damage before luck, shared with the AI's estimates: the formula's base (power after
## abilities, stats after stages), the multipliers on it (STAB, type, the defender's ability,
## items, weather and surge), the screens' multiplier (which a critical hit ignores) and the
## compressed effectiveness. An ability immunity counts as a type immunity (§9.9).
static func damage_parts(attacker: Fighter, defender: Fighter, move: BattleMove, data: BattleData) -> Dictionary:
	var attack := move.attack_stat(attacker, defender)
	var defense := defender.stat(attacker.arena.defensive_stat(move))
	var power := move.power * Abilities.power_factor(attacker, move)
	var base := floorf(floorf(floorf(2.0 * Rules.LEVEL / 5.0 + 2.0) * power * attack / defense) / 50.0) + 2.0
	var stab := Abilities.stab(attacker) if move.type in attacker.types else 1.0
	var defender_types := defender.types
	# Gravity grounds Flying types: Ground moves reach them as if they weren't Flying.
	if move.type == "Ground" and "Flying" in defender_types and attacker.arena.has_field("gravity"):
		defender_types = defender_types.filter(func(type: String) -> bool: return type != "Flying")
	var main_series := Abilities.effectiveness(attacker, defender, move, data.effectiveness(move.type, defender_types))
	var effectiveness := Rules.compressed_effectiveness(main_series)
	var factor := stab * effectiveness * Abilities.taken_factor(defender, move, main_series) * Items.power_factor(attacker, move, main_series) 		* attacker.arena.damage_factor(attacker, defender, move)
	if attacker.helped:
		factor *= Rules.HELPING_HAND_FACTOR
	# Friend Guard: the defender's ally (doubles) softens hits on it.
	if defender.ally != null and not defender.ally.is_knocked_out() and defender.ally.ability_effect.has("ally_taken"):
		factor *= float(defender.ally.ability_effect.ally_taken)
	return {"base": base, "factor": factor, "screen": attacker.arena.screen_factor(attacker, defender, move),
		"effectiveness": effectiveness}


func _check_end() -> void:
	var a_down := healthy(0).is_empty()
	var b_down := healthy(1).is_empty()
	if a_down and b_down:
		result = Result.DRAW
	elif b_down:
		result = Result.WIN_A
	elif a_down:
		result = Result.WIN_B
	elif tick >= _time_cap_ticks:
		result = _time_up_result()
		_event("time_up", -1, {})


## Who wins at time-up: in a team battle the side with more Pokémon left, then the higher share
## of its team's HP left; otherwise (and when even) a draw.
func _time_up_result() -> Result:
	if not _hash_teams:
		return Result.DRAW
	var left := [healthy(0).size(), healthy(1).size()]
	if left[0] != left[1]:
		return Result.WIN_A if left[0] > left[1] else Result.WIN_B
	var shares := [0.0, 0.0]
	for side in 2:
		var hp := 0
		var full := 0
		for fighter: Fighter in teams[side]:
			hp += fighter.hp
			full += fighter.max_hp
		shares[side] = float(hp) / maxi(full, 1)
	if is_equal_approx(shares[0], shares[1]):
		return Result.DRAW
	return Result.WIN_A if shares[0] > shares[1] else Result.WIN_B


## Hashes every value that defines the state. Runs every tick, so it fills a reused array.
func _record_state() -> void:
	_state.resize(FIGHTER_STATE_SIZE * fighters.size() + 4 + 2 * ArenaConditions.SCREENS.size() + FIELD_STATE_SIZE + projectiles.size() * 3
		+ (TEAM_STATE_SIZE * 2 if _hash_teams else 0) + ((PLACE_STATE_SIZE * fighters.size() + 4) if doubles else 0))
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
	_state[i + 2] = ArenaConditions.SURGES.find(conditions.surge)
	_state[i + 3] = conditions.surge_ticks
	i += 4
	for side in 2:
		for screen in ArenaConditions.SCREENS:
			_state[i] = conditions.screens[side].get(screen, 0)
			i += 1
		for condition in ArenaConditions.SIDE_CONDITIONS:
			_state[i] = conditions.sides[side].get(condition, 0)
			i += 1
	for name in ArenaConditions.FIELDS:
		_state[i] = conditions.field.get(name, 0)
		i += 1
	for projectile in projectiles:
		_state[i] = projectile.position.x
		_state[i + 1] = projectile.position.y
		_state[i + 2] = projectile.height
		i += 3
	if _hash_teams:
		for side in 2:
			_state[i] = fighters[side].slot
			_state[i + 1] = _send_out_ticks[side]
			_state[i + 2] = 1.0 if fighters[side].shielded else 0.0
			_state[i + 3] = _switch_cooldown[side]
			for h in ArenaConditions.HAZARDS.size():
				_state[i + 4 + h] = int(conditions.hazards[side].get(ArenaConditions.HAZARDS.keys()[h], 0))
			i += TEAM_STATE_SIZE
	if doubles:
		for index in fighters.size():
			_state[i] = fighters[index].slot
			_state[i + 1] = _send_out_ticks[index]
			_state[i + 2] = 1.0 if fighters[index].shielded else 0.0
			_state[i + 3] = fighters[index].target_place
			_state[i + 4] = fighters[index].helping_ticks
			_state[i + 5] = fighters[index].cheer_ticks
			_state[i + 6] = 1.0 if fighters[index].helped else 0.0
			i += PLACE_STATE_SIZE
		for side in 2:
			_state[i] = _redirects[side].get("ticks", 0)
			_state[i + 1] = _wide_guard[side]
			i += 2
	_hash.update(_state.to_byte_array())


## Records an event. One by a side names a team slot ("slot"): its first fighter out's unless
## `details` says otherwise.
func _event(type: String, side: int, details: Dictionary) -> void:
	var event := {"tick": tick, "type": type, "side": side}
	if side >= 0:
		event.slot = fighters[side].slot
	event.merge(details, true)
	events.append(event)


## In doubles, `details` naming the fighter an event is aimed at (or, for "guarded", the attacker
## blocked): its "target_side" and "target_slot". Singles events stay as they were.
func _aimed(at: Fighter, details: Dictionary) -> Dictionary:
	if doubles:
		details.target_side = at.side
		details.target_slot = at.slot
	return details


## Records an event about one fighter: its side and team slot.
func _fevent(type: String, fighter: Fighter, details: Dictionary) -> void:
	var event := {"tick": tick, "type": type, "side": fighter.side, "slot": fighter.slot}
	event.merge(details, true)
	events.append(event)
