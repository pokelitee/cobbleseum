class_name Highlights
extends RefCounted
## Picks the clip window (concepts_brief.md §12.6): the stretch of a planned battle that fills
## the requested video length with the most excitement. Events score by weight: big hits,
## crits, super-effective hits and comebacks (hits by a fighter low on HP) count most, then
## dodges, blocks and parries, and the knockout or time-up counts so much that clips usually
## end on it. A window ends either where the plan ends or a short linger after a hit, so it
## always closes on a payoff; a window that reaches the finish always plays the whole knockout
## to the end, and then the victory, which comes on top of the requested length rather than
## out of it.

const HIT_SCORE := 1.0
## Added per share of the defender's max HP the hit took.
const DAMAGE_SCORE := 4.0
const CRIT_SCORE := 1.0
const SUPER_EFFECTIVE_SCORE := 1.0
## Hits landed while the attacker is at or below COMEBACK_HP of its max HP.
const COMEBACK_SCORE := 1.5
const COMEBACK_HP := 0.3
const MISS_SCORE := 0.3
## An attack avoided by dodging through it.
const DODGED_SCORE := 1.0
## An attack stopped by a guard, more for a parry (it opens a punish window).
const GUARDED_SCORE := 1.0
const PARRY_SCORE := 1.5
const STATUS_SCORE := 1.0
const BOOST_SCORE := 0.4
const HEAL_SCORE := 0.6
const KNOCKOUT_SCORE := 8.0
const TIME_UP_SCORE := 4.0
## Ticks kept after a window's last hit, so the reaction plays out.
const END_LINGER_TICKS := 20


## A hit event's defender: its "target_side", or the other side in events from before teams.
static func defender(event: Dictionary) -> int:
	return int(event.get("target_side", 1 - int(event.side)))


## Max HP from `max_hp`, which is per side ([side A's, side B's]) or per side and team slot
## (Battle.team_max_hp()).
static func max_hp_of(max_hp: Array, side: int, slot: int) -> float:
	var entry: Variant = max_hp[side]
	return float(entry[slot]) if entry is Array else float(entry)


## Whether a knockout event ends the battle: its side has no one left.
static func is_final(event: Dictionary) -> bool:
	return int(event.get("left", 0)) == 0


## The best window covering at least `frames` video frames, or the whole plan when it is
## shorter: {"start": tick, "end": tick (exclusive), "score": float}. Ties go to the later
## window, which is closer to the finish.
static func choose(plan_data: Dictionary, events: Array, max_hp: Array, frames: int) -> Dictionary:
	var victory: Dictionary = plan_data.get("victory", {})
	var length: int = int(victory.start) if not victory.is_empty() else plan_data.slow.size()
	var frames_at := PackedInt32Array()
	frames_at.resize(length)
	for t in length:
		frames_at[t] = plan_data.slow[t] + plan_data.hitstop[t]
	var scores := event_scores(events, max_hp)
	var finish := length
	for event: Dictionary in events:
		if event.type == "time_up" or (event.type == "knockout" and is_final(event)):
			finish = mini(finish, int(event.tick))
	var ends: Array[int] = [length]
	for i in events.size():
		if events[i].type == "hit":
			var end := int(events[i].tick) + 1 + END_LINGER_TICKS
			end = length if end > finish else end
			if not ends.has(end):
				ends.append(end)
	var best := {}
	for end in ends:
		var start := _start_for(frames_at, end, frames)
		var score := 0.0
		for i in events.size():
			var tick: int = events[i].tick
			if tick >= start and tick < end:
				score += scores[i]
		if best.is_empty() or score > best.score or (is_equal_approx(score, best.score) and end > best.end):
			best = {"start": start, "end": end, "score": score}
	if best.end == length:
		best.end = plan_data.slow.size()
	return best


## One score per event, in the log's order.
static func event_scores(events: Array, max_hp: Array) -> PackedFloat32Array:
	var comebacks := comeback_hits(events, max_hp)
	var scores := PackedFloat32Array()
	scores.resize(events.size())
	for i in events.size():
		var event: Dictionary = events[i]
		match event.type:
			"hit":
				var score := HIT_SCORE + DAMAGE_SCORE * float(event.damage) / max_hp_of(max_hp, defender(event),
					int(event.get("target_slot", 0)))
				if event.crit:
					score += CRIT_SCORE
				if float(event.effectiveness) > 1.0:
					score += SUPER_EFFECTIVE_SCORE
				if comebacks.has(i):
					score += COMEBACK_SCORE
				scores[i] = score
			"miss":
				scores[i] = MISS_SCORE
			"dodged":
				scores[i] = DODGED_SCORE
			"guarded":
				scores[i] = PARRY_SCORE if event.get("parry", false) else GUARDED_SCORE
			"status":
				scores[i] = STATUS_SCORE
			"boost":
				scores[i] = BOOST_SCORE
			"heal":
				scores[i] = HEAL_SCORE
			"knockout":
				scores[i] = KNOCKOUT_SCORE
			"time_up":
				scores[i] = TIME_UP_SCORE
	return scores


## Indices of the hits landed by a fighter at or below COMEBACK_HP of its max HP, in the
## log's order. HP is tracked from the hits alone, per side and team slot.
static func comeback_hits(events: Array, max_hp: Array) -> Array[int]:
	var hp := {}
	var found: Array[int] = []
	for i in events.size():
		var event: Dictionary = events[i]
		if event.type != "hit":
			continue
		var attacker: int = event.side
		var slot := int(event.get("slot", 0))
		var full := max_hp_of(max_hp, attacker, slot)
		if float(hp.get(Vector2i(attacker, slot), full)) <= COMEBACK_HP * full:
			found.append(i)
		hp[Vector2i(defender(event), int(event.get("target_slot", 0)))] = float(event.hp)
	return found


## The latest start tick from which [start, end) fills at least `frames` video frames.
static func _start_for(frames_at: PackedInt32Array, end: int, frames: int) -> int:
	var total := 0
	for t in range(end - 1, -1, -1):
		total += frames_at[t]
		if total >= frames:
			return t
	return 0
