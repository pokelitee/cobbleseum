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
## The knockout and the victory cut in on time, whatever shot they interrupt.
const FORCED_CUTS: Array[Shot] = [Shot.KNOCKOUT, Shot.VICTORY]
## Every shot holds at least this long (about a second), so the edit never jitters.
const MIN_SHOT_TICKS := 30
const BASE_SHOT_MIN_TICKS := 150
const BASE_SHOT_MAX_TICKS := 270
## A wind-up gets a close-up when its move is at least this strong. The close-up covers the
## CLOSE_UP_TICKS before the move's release, starting before the wind-up when that is shorter,
## so it can hold long enough and arrives as the move goes off.
const CLOSE_UP_POWER := 90
const CLOSE_UP_TICKS := 30
## A close-up waits this long after the last close-up or punch-in, so the wide and
## over-the-shoulder shots get room between them.
const CLOSE_UP_GAP_TICKS := 60
## Projectiles get a tracking shot when they fly at least this long.
const TRACKING_MIN_TICKS := 15
const IMPACT_TICKS := 30
## A hit is "heavy" (punch-in, longer hit-stop) at this share of the defender's max HP.
const HEAVY_HIT_SHARE := 0.1
const HITSTOP_FRAMES := 2
const HEAVY_HITSTOP_FRAMES := 5
## Knockout slow motion: frames per tick, and how long it lingers after the knockout.
const KNOCKOUT_FRAMES_PER_TICK := 3
const KNOCKOUT_LINGER_TICKS := 30
## After a knockout, the winner's victory shot (and the HUD's victory card) at normal speed.
const VICTORY_TICKS := 75
## The instant replay, shown between the knockout's linger and the victory: from this many
## ticks before the knockout (or the finishing move's wind-up, if later) to this many after
## it, at this many frames per tick.
const REPLAY_BEFORE_TICKS := 24
const REPLAY_AFTER_TICKS := 12
const REPLAY_FRAMES_PER_TICK := 2
## The longest replay, in video frames.
const REPLAY_MAX_FRAMES := (REPLAY_BEFORE_TICKS + REPLAY_AFTER_TICKS + 1) * REPLAY_FRAMES_PER_TICK
## Caption texts (concepts_brief.md §12.5).
const COMEBACK_CAPTION := "COMEBACK!"
const FINAL_BLOW_CAPTION := "FINAL BLOW"


## Before a knockout that isn't the last, slow motion starts no earlier than this many ticks
## before it (a knockout by a status condition has no wind-up of its own).
const KNOCKOUT_LEAD_TICKS := 45


## events: the battle's event log. end_tick: the tick the battle ended. max_hp: per side, or per
## side and team slot (Battle.team_max_hp()).
## move_power: per side, move id -> base power. Covers ticks [0, end_tick + linger), plus the
## victory after a knockout; ticks from end_tick on are presentation-only (the battle is over,
## the knockout plays out, the winner celebrates). Returns:
##   "hitstop": PackedInt32Array, frozen frames shown before each tick advances
##   "slow": PackedInt32Array, frames each tick lasts after any hit-stop (1, or more in slow motion)
##   "shots": Array of {"start", "end", "shot", "side"}, and in doubles "slot" for a shot on one
##     fighter (the attacker of a close-up or tracking shot, the one hit or knocked out); a
##     doubles shot without one (wide, over-the-shoulder, victory) is the side's
## Every knockout gets its slow-motion orbit; only the last one (its side has no one left) gets
## the victory and the instant replay.
##   "victory": {"start": tick, "side": the winner} after a knockout, else {}
##   "replay": after a knockout, the instant replay that plays just before the victory:
##     {"at": the victory's start tick, "start", "end": the replayed ticks [start, end),
##     "knockout": tick, "frames_per_tick", "shots": like "shots", over the replayed ticks};
##     else {}
##   "captions": Array of {"tick", "text", "side"} in tick order: "COMEBACK!" on each
##     fighter's first hit while low on HP (as Highlights counts comebacks), "FINAL BLOW" on
##     the finishing move's wind-up
static func plan(events: Array, end_tick: int, max_hp: Array, move_power: Array, random: SimRandom, doubles := false) -> Dictionary:
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
	var busy_until := -CLOSE_UP_GAP_TICKS
	for i in events.size():
		var event: Dictionary = events[i]
		match event.type:
			"windup":
				if int(move_power[event.side].get(event.move, 0)) >= CLOSE_UP_POWER:
					var release := _next_tick(events, i, event.side, ["fire", "hit", "miss"], event.tick + 15, _slot_of(event, doubles))
					var start := mini(event.tick, release - CLOSE_UP_TICKS)
					if start >= busy_until + CLOSE_UP_GAP_TICKS:
						_overlay(shot_at, side_at, start, release, Shot.CLOSE_UP, _focus(event.side, _slot_of(event, doubles)))
						busy_until = release
			"fire":
				var landed := _next_tick(events, i, event.side, ["hit", "miss"], -1, _slot_of(event, doubles))
				if landed - event.tick >= TRACKING_MIN_TICKS:
					_overlay(shot_at, side_at, event.tick, landed, Shot.TRACKING, _focus(event.side, _slot_of(event, doubles)))
			"hit":
				var defender := Highlights.defender(event)
				var heavy: bool = event.crit or event.effectiveness > 1.0 \
					or float(event.damage) >= HEAVY_HIT_SHARE * Highlights.max_hp_of(max_hp, defender, int(event.get("target_slot", 0)))
				if event.tick < length:
					hitstop[event.tick] += HEAVY_HITSTOP_FRAMES if heavy else HITSTOP_FRAMES
				if heavy:
					var hit_slot := int(event.get("target_slot", 0)) if doubles else -1
					_overlay(shot_at, side_at, event.tick, event.tick + IMPACT_TICKS, Shot.IMPACT, _focus(defender, hit_slot))
					busy_until = maxi(busy_until, event.tick + IMPACT_TICKS)
	for earlier: Dictionary in _earlier_knockouts(events):
		var orbit_end: int = mini(int(earlier.tick) + KNOCKOUT_LINGER_TICKS, length)
		_overlay(shot_at, side_at, earlier.start, orbit_end, Shot.KNOCKOUT, _focus(earlier.loser, earlier.slot if doubles else -1))
		for tick in range(earlier.start, orbit_end):
			slow[tick] = KNOCKOUT_FRAMES_PER_TICK
	var victory := {}
	if not knockout.is_empty():
		_overlay(shot_at, side_at, knockout.start, victory_start, Shot.KNOCKOUT, _focus(knockout.loser, knockout.slot if doubles else -1))
		for tick in range(knockout.start, victory_start):
			slow[tick] = KNOCKOUT_FRAMES_PER_TICK
		victory = {"start": victory_start, "side": 1 - int(knockout.loser)}
		_overlay(shot_at, side_at, victory_start, length, Shot.VICTORY, victory.side)
	return {"hitstop": hitstop, "slow": slow, "shots": _calm(_segments(shot_at, side_at)), "victory": victory,
		"replay": _replay(knockout, victory_start, doubles), "captions": _captions(events, max_hp, knockout)}


## The team slot of the fighter an event names, in doubles; -1 in singles (a shot on the side).
static func _slot_of(event: Dictionary, doubles: bool) -> int:
	return int(event.get("slot", 0)) if doubles else -1


## A shot's focus as side_at keeps it: the side, or (slot >= 0, doubles) one fighter of it,
## side + 2 * (slot + 1); _segments reads it back as "side" and "slot".
static func _focus(side: int, slot := -1) -> int:
	return side if slot < 0 else side + 2 * (slot + 1)


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


## Asks for `shot` over ticks [start, end) where nothing more important is asked for. Only the
## knockout and the victory may start before the opening wide shot has held MIN_SHOT_TICKS.
static func _overlay(shot_at: PackedInt32Array, side_at: PackedInt32Array, start: int, end: int, shot: Shot, side: int) -> void:
	var first := 0 if shot in FORCED_CUTS else MIN_SHOT_TICKS
	for t in range(maxi(start, first), mini(end, shot_at.size())):
		if PRIORITY.find(shot) >= PRIORITY.find(shot_at[t] as Shot):
			shot_at[t] = shot
			side_at[t] = side


## The knockouts before the final one, each as {"start", "loser", "tick"}: slow motion from
## the finishing move's wind-up, at most KNOCKOUT_LEAD_TICKS before the knockout.
static func _earlier_knockouts(events: Array) -> Array:
	var found: Array = []
	for i in events.size():
		var event: Dictionary = events[i]
		if event.type != "knockout" or Highlights.is_final(event):
			continue
		var start := maxi(0, int(event.tick) - 15)
		for j in range(i - 1, -1, -1):
			if _finishing_windup(events[j], event):
				if int(events[j].tick) >= int(event.tick) - KNOCKOUT_LEAD_TICKS:
					start = events[j].tick
				break
		found.append({"start": start, "loser": event.side, "slot": int(event.get("slot", 0)), "tick": event.tick})
	return found


## Whether `windup` could be the wind-up of the move behind `knockout`: one by the other side,
## aimed at the fighter knocked out where the event says (doubles).
static func _finishing_windup(windup: Dictionary, knockout: Dictionary) -> bool:
	if windup.type != "windup" or windup.side != 1 - int(knockout.side):
		return false
	return not windup.has("target_side") or int(windup.get("target_slot", 0)) == int(knockout.get("slot", 0))


## Slow motion starts at the wind-up of the move that caused the knockout ("windup" is -1
## when there was none). Only the final knockout counts.
static func _knockout_window(events: Array, end_tick: int) -> Dictionary:
	for i in range(events.size() - 1, -1, -1):
		var event: Dictionary = events[i]
		if event.type != "knockout" or not Highlights.is_final(event):
			continue
		var loser: int = event.side
		var slot := int(event.get("slot", 0))
		for j in range(i - 1, -1, -1):
			if _finishing_windup(events[j], event):
				return {"start": events[j].tick, "loser": loser, "slot": slot, "tick": event.tick, "windup": events[j].tick,
					"attacker": int(events[j].get("slot", 0))}
		return {"start": maxi(0, end_tick - 15), "loser": loser, "slot": slot, "tick": event.tick, "windup": -1, "attacker": -1}
	return {}


## The instant replay: the attacker's side from a low over-the-shoulder angle into the hit,
## then a punch-in on the loser through the faint.
static func _replay(knockout: Dictionary, at: int, doubles := false) -> Dictionary:
	if knockout.is_empty():
		return {}
	var hit: int = knockout.tick
	var start := maxi(maxi(0, hit - REPLAY_BEFORE_TICKS), int(knockout.windup))
	var end := hit + REPLAY_AFTER_TICKS + 1
	var loser: int = knockout.loser
	var shots: Array = []
	if start < hit:
		var shoulder := {"start": start, "end": hit, "shot": Shot.OVER_SHOULDER, "side": 1 - loser, "low": true}
		if doubles and int(knockout.attacker) >= 0:
			shoulder.slot = int(knockout.attacker)
			shoulder.target_slot = int(knockout.slot)
		shots.append(shoulder)
	var impact := {"start": hit, "end": end, "shot": Shot.IMPACT, "side": loser}
	if doubles:
		impact.slot = int(knockout.slot)
	shots.append(impact)
	return {"at": at, "start": start, "end": end, "knockout": hit, "frames_per_tick": REPLAY_FRAMES_PER_TICK, "shots": shots}


## Captions, kept off the knockout's slow motion except for "FINAL BLOW", so one never
## replaces it.
static func _captions(events: Array, max_hp: Array, knockout: Dictionary) -> Array:
	var captions: Array = []
	var finish: int = knockout.start if not knockout.is_empty() else 1 << 30
	var shown := [false, false]
	for i in Highlights.comeback_hits(events, max_hp):
		var event: Dictionary = events[i]
		if not shown[event.side] and int(event.tick) < finish:
			shown[event.side] = true
			captions.append({"tick": event.tick, "text": COMEBACK_CAPTION, "side": event.side})
	if not knockout.is_empty() and int(knockout.windup) >= 0:
		captions.append({"tick": knockout.windup, "text": FINAL_BLOW_CAPTION, "side": 1 - int(knockout.loser)})
	return captions


## Tick of the next event by `side` (and in doubles its fighter in team `slot`, unless -1) with
## one of `types` after index `from`, or `fallback`.
static func _next_tick(events: Array, from: int, side: int, types: Array, fallback: int, slot := -1) -> int:
	for j in range(from + 1, events.size()):
		if events[j].side == side and events[j].type in types and (slot < 0 or int(events[j].get("slot", 0)) == slot):
			return events[j].tick
	return fallback


## The edit with every shot held at least MIN_SHOT_TICKS (concepts_brief.md §12.3), from the
## segments each tick asked for. A shot asked for while the current one is still too short is
## pushed back to when it has held long enough, if enough of it is left then, and otherwise
## dropped, the current shot running on over it. A more important shot (higher in PRIORITY)
## doesn't wait: the short shot before it is dropped instead, its time going to the shot
## before that. The knockout and the victory always cut in on time. The opening shot is never
## dropped, so battles open wide.
static func _calm(asked: Array) -> Array:
	var shots: Array = []
	for segment: Dictionary in asked:
		var next := segment.duplicate()
		while true:
			if shots.is_empty():
				shots.append(next)
				break
			var current: Dictionary = shots[-1]
			if _same_shot(current, next):
				current.end = next.end
				break
			var held := int(next.start) - int(current.start)
			if held >= MIN_SHOT_TICKS:
				shots.append(next)
				break
			var forced: bool = next.shot in FORCED_CUTS
			if shots.size() > 1 and (forced or _rank(next) > _rank(current)):
				shots.pop_back()
				shots[-1].end = current.end
				continue
			if forced:
				shots.append(next)
				break
			var cut := int(current.start) + MIN_SHOT_TICKS
			if int(next.end) - cut >= MIN_SHOT_TICKS:
				current.end = cut
				next.start = cut
				shots.append(next)
			else:
				current.end = next.end
			break
	return shots


static func _same_shot(a: Dictionary, b: Dictionary) -> bool:
	return a.shot == b.shot and a.side == b.side and a.get("slot", -1) == b.get("slot", -1)


static func _rank(segment: Dictionary) -> int:
	return PRIORITY.find(segment.shot as Shot)


static func _segments(shot_at: PackedInt32Array, side_at: PackedInt32Array) -> Array:
	var segments: Array = []
	for t in shot_at.size():
		if segments.is_empty() or segments[-1].shot != shot_at[t] or segments[-1].focus != side_at[t]:
			segments.append({"start": t, "end": t + 1, "shot": shot_at[t], "focus": side_at[t]})
		else:
			segments[-1].end = t + 1
	for segment: Dictionary in segments:
		var focus: int = segment.focus
		segment.erase("focus")
		segment.side = focus % 2
		if focus >= 2:
			segment.slot = focus / 2 - 1
	return segments
