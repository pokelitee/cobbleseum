class_name Director
extends RefCounted
## Plans how a finished battle is presented (concepts_brief.md §12.2, §12.3): how many video
## frames each simulation tick occupies (hit-stop, slow motion) and which camera shot covers
## each tick. Planning reads the whole event log, so it can build up to moments such as the
## knockout and the winner's victory shot after it. Choices draw only from the battle's
## cosmetic stream, so a battle always gets the same edit.

enum Shot { WIDE, OVER_SHOULDER, CLOSE_UP, TRACKING, IMPACT, KNOCKOUT, VICTORY }

## Shots that may interrupt others, highest priority last.
const PRIORITY: Array[Shot] = [Shot.WIDE, Shot.OVER_SHOULDER, Shot.TRACKING, Shot.CLOSE_UP, Shot.IMPACT, Shot.KNOCKOUT, Shot.VICTORY]
const BASE_SHOT_MIN_TICKS := 90
const BASE_SHOT_MAX_TICKS := 180
## A wind-up gets a close-up when its move is at least this strong.
const CLOSE_UP_POWER := 90
## Projectiles get a tracking shot when they fly at least this long.
const TRACKING_MIN_TICKS := 8
const IMPACT_TICKS := 12
## A hit is "heavy" (punch-in, longer hit-stop) at this share of the defender's max HP.
const HEAVY_HIT_SHARE := 0.1
const HITSTOP_FRAMES := 2
const HEAVY_HITSTOP_FRAMES := 5
## Knockout slow motion: frames per tick, and how long it lingers after the knockout.
const KNOCKOUT_FRAMES_PER_TICK := 3
const KNOCKOUT_LINGER_TICKS := 30
## After a knockout, the winner's victory shot (and the HUD's victory card) at normal speed.
const VICTORY_TICKS := 75


## events: the battle's event log. end_tick: the tick the battle ended. max_hp: per side.
## move_power: per side, move id -> base power. Covers ticks [0, end_tick + linger), plus the
## victory after a knockout; ticks from end_tick on are presentation-only (the battle is over,
## the knockout plays out, the winner celebrates). Returns:
##   "hitstop": PackedInt32Array, frozen frames shown before each tick advances
##   "slow": PackedInt32Array, frames each tick lasts after any hit-stop (1, or more in slow motion)
##   "shots": Array of {"start", "end", "shot", "side"}
##   "victory": {"start": tick, "side": the winner} after a knockout, else {}
static func plan(events: Array, end_tick: int, max_hp: Array, move_power: Array, random: SimRandom) -> Dictionary:
	var knockout := _knockout_window(events, end_tick)
	var victory_start := end_tick + KNOCKOUT_LINGER_TICKS
	var length := victory_start + (VICTORY_TICKS if not knockout.is_empty() else 0)
	var hitstop := PackedInt32Array()
	hitstop.resize(length)
	var slow := PackedInt32Array()
	slow.resize(length)
	slow.fill(1)
	var shot_at := PackedInt32Array()
	shot_at.resize(length)
	var side_at := PackedInt32Array()
	side_at.resize(length)

	_base_shots(shot_at, side_at, random)
	for i in events.size():
		var event: Dictionary = events[i]
		match event.type:
			"windup":
				if int(move_power[event.side].get(event.move, 0)) >= CLOSE_UP_POWER:
					var release := _next_tick(events, i, event.side, ["fire", "hit", "miss"], event.tick + 15)
					_overlay(shot_at, side_at, event.tick, release, Shot.CLOSE_UP, event.side)
			"fire":
				var landed := _next_tick(events, i, event.side, ["hit", "miss"], -1)
				if landed - event.tick >= TRACKING_MIN_TICKS:
					_overlay(shot_at, side_at, event.tick, landed, Shot.TRACKING, event.side)
			"hit":
				var defender := 1 - int(event.side)
				var heavy: bool = event.crit or event.effectiveness > 1.0 or float(event.damage) >= HEAVY_HIT_SHARE * float(max_hp[defender])
				if event.tick < length:
					hitstop[event.tick] += HEAVY_HITSTOP_FRAMES if heavy else HITSTOP_FRAMES
				if heavy:
					_overlay(shot_at, side_at, event.tick, event.tick + IMPACT_TICKS, Shot.IMPACT, defender)
	var victory := {}
	if not knockout.is_empty():
		_overlay(shot_at, side_at, knockout.start, victory_start, Shot.KNOCKOUT, knockout.loser)
		for tick in range(knockout.start, victory_start):
			slow[tick] = KNOCKOUT_FRAMES_PER_TICK
		victory = {"start": victory_start, "side": 1 - int(knockout.loser)}
		_overlay(shot_at, side_at, victory_start, length, Shot.VICTORY, victory.side)
	return {"hitstop": hitstop, "slow": slow, "shots": _segments(shot_at, side_at), "victory": victory}


## Video frames from `tick` to the end of the plan.
static func frames_from(plan_data: Dictionary, tick: int) -> int:
	var total := 0
	for t in range(tick, plan_data.slow.size()):
		total += plan_data.slow[t] + plan_data.hitstop[t]
	return total


## The shot covering a tick (the last one if the tick is past the plan).
static func shot_for(shots: Array, tick: int) -> Dictionary:
	for segment: Dictionary in shots:
		if tick < segment.end:
			return segment
	return shots[-1]


## Alternates wide and over-the-shoulder shots of random length, starting wide.
static func _base_shots(shot_at: PackedInt32Array, side_at: PackedInt32Array, random: SimRandom) -> void:
	var tick := 0
	var wide := true
	while tick < shot_at.size():
		var length := BASE_SHOT_MIN_TICKS + int(random.next_u32() % (BASE_SHOT_MAX_TICKS - BASE_SHOT_MIN_TICKS + 1))
		var side := int(random.next_u32() % 2)
		for t in range(tick, mini(tick + length, shot_at.size())):
			shot_at[t] = Shot.WIDE if wide else Shot.OVER_SHOULDER
			side_at[t] = side
		tick += length
		wide = not wide


static func _overlay(shot_at: PackedInt32Array, side_at: PackedInt32Array, start: int, end: int, shot: Shot, side: int) -> void:
	for t in range(maxi(start, 0), mini(end, shot_at.size())):
		if PRIORITY.find(shot) >= PRIORITY.find(shot_at[t] as Shot):
			shot_at[t] = shot
			side_at[t] = side


## Slow motion starts at the wind-up of the move that caused the knockout.
static func _knockout_window(events: Array, end_tick: int) -> Dictionary:
	for i in range(events.size() - 1, -1, -1):
		var event: Dictionary = events[i]
		if event.type != "knockout":
			continue
		var loser: int = event.side
		for j in range(i - 1, -1, -1):
			if events[j].type == "windup" and events[j].side == 1 - loser:
				return {"start": events[j].tick, "loser": loser}
		return {"start": maxi(0, end_tick - 15), "loser": loser}
	return {}


## Tick of the next event by `side` with one of `types` after index `from`, or `fallback`.
static func _next_tick(events: Array, from: int, side: int, types: Array, fallback: int) -> int:
	for j in range(from + 1, events.size()):
		if events[j].side == side and events[j].type in types:
			return events[j].tick
	return fallback


static func _segments(shot_at: PackedInt32Array, side_at: PackedInt32Array) -> Array:
	var segments: Array = []
	for t in shot_at.size():
		if segments.is_empty() or segments[-1].shot != shot_at[t] or segments[-1].side != side_at[t]:
			segments.append({"start": t, "end": t + 1, "shot": shot_at[t], "side": side_at[t]})
		else:
			segments[-1].end = t + 1
	return segments
