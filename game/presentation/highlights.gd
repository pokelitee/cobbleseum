class_name Highlights
extends RefCounted
## Picks the clip window (concepts_brief.md §12.6): the stretch of a planned battle that fills
## the requested video length with the most excitement. Events score by weight: big hits,
## crits, super-effective hits and comebacks (hits by a fighter low on HP) count most, and the
## knockout or time-up counts so much that clips usually end on it. A window ends either
## where the plan ends or a short linger after a hit, so it always closes on a payoff; a
## window that reaches the finish always plays the whole knockout to the end.

const HIT_SCORE := 1.0
## Added per share of the defender's max HP the hit took.
const DAMAGE_SCORE := 4.0
const CRIT_SCORE := 1.0
const SUPER_EFFECTIVE_SCORE := 1.0
## Hits landed while the attacker is at or below COMEBACK_HP of its max HP.
const COMEBACK_SCORE := 1.5
const COMEBACK_HP := 0.3
const MISS_SCORE := 0.3
const FAINT_SCORE := 8.0
const TIME_UP_SCORE := 4.0
## Ticks kept after a window's last hit, so the reaction plays out.
const END_LINGER_TICKS := 20


## The best window covering at least `frames` video frames, or the whole plan when it is
## shorter: {"start": tick, "end": tick (exclusive), "score": float}. Ties go to the later
## window, which is closer to the finish.
static func choose(plan_data: Dictionary, events: Array, max_hp: Array, frames: int) -> Dictionary:
	var length: int = plan_data.slow.size()
	var frames_at := PackedInt32Array()
	frames_at.resize(length)
	for t in length:
		frames_at[t] = plan_data.slow[t] + plan_data.hitstop[t]
	var scores := event_scores(events, max_hp)
	var finish := length
	for event: Dictionary in events:
		if event.type in ["faint", "time_up"]:
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
	return best


## One score per event, in the log's order.
static func event_scores(events: Array, max_hp: Array) -> PackedFloat32Array:
	var hp := [float(max_hp[0]), float(max_hp[1])]
	var scores := PackedFloat32Array()
	scores.resize(events.size())
	for i in events.size():
		var event: Dictionary = events[i]
		match event.type:
			"hit":
				var attacker: int = event.side
				var defender := 1 - attacker
				var score := HIT_SCORE + DAMAGE_SCORE * float(event.damage) / float(max_hp[defender])
				if event.crit:
					score += CRIT_SCORE
				if float(event.effectiveness) > 1.0:
					score += SUPER_EFFECTIVE_SCORE
				if hp[attacker] <= COMEBACK_HP * float(max_hp[attacker]):
					score += COMEBACK_SCORE
				scores[i] = score
				hp[defender] = float(event.hp)
			"miss":
				scores[i] = MISS_SCORE
			"faint":
				scores[i] = FAINT_SCORE
			"time_up":
				scores[i] = TIME_UP_SCORE
	return scores


## The latest start tick from which [start, end) fills at least `frames` video frames.
static func _start_for(frames_at: PackedInt32Array, end: int, frames: int) -> int:
	var total := 0
	for t in range(end - 1, -1, -1):
		total += frames_at[t]
		if total >= frames:
			return t
	return 0
