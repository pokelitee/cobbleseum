extends TestCase

const MAX_HP := [400, 400]
const MOVE_POWER := [{"jet": 80, "cannon": 110}, {"kick": 60}]


## Side 0 fires a weak projectile, lands a crit, then winds up a strong move that knocks
## side 1 out at tick 300.
func _events() -> Array:
	return [
		{"tick": 10, "type": "windup", "side": 0, "move": "jet"},
		{"tick": 20, "type": "fire", "side": 0, "move": "jet"},
		{"tick": 40, "type": "hit", "side": 0, "move": "jet", "damage": 20, "crit": false, "effectiveness": 1.0, "hp": 380},
		{"tick": 100, "type": "hit", "side": 1, "move": "kick", "damage": 30, "crit": true, "effectiveness": 1.0, "hp": 370},
		{"tick": 280, "type": "windup", "side": 0, "move": "cannon"},
		{"tick": 295, "type": "fire", "side": 0, "move": "cannon"},
		{"tick": 300, "type": "hit", "side": 0, "move": "cannon", "damage": 380, "crit": false, "effectiveness": 1.3, "hp": 0},
		{"tick": 300, "type": "knockout", "side": 1},
	]


func _plan(seed := 1) -> Dictionary:
	return Director.plan(_events(), 301, MAX_HP, MOVE_POWER, SimRandom.new(seed))


func test_plan_covers_battle_knockout_linger_and_victory() -> void:
	var plan := _plan()
	assert_eq(plan.slow.size(), 301 + Director.KNOCKOUT_LINGER_TICKS + Director.VICTORY_TICKS)
	assert_eq(plan.hitstop.size(), plan.slow.size())
	assert_eq(plan.shots[0].start, 0)
	assert_eq(plan.shots[-1].end, plan.slow.size())
	for i in range(1, plan.shots.size()):
		assert_eq(plan.shots[i].start, plan.shots[i - 1].end, "shots are contiguous")


func test_hits_get_hitstop_scaled_by_weight() -> void:
	var plan := _plan()
	assert_eq(plan.hitstop[40], Director.HITSTOP_FRAMES, "light hit")
	assert_eq(plan.hitstop[100], Director.HEAVY_HITSTOP_FRAMES, "critical hit")
	assert_eq(plan.hitstop[50], 0)


func test_knockout_slow_motion_starts_at_the_final_windup() -> void:
	var plan := _plan()
	assert_eq(plan.slow[279], 1)
	assert_eq(plan.slow[280], Director.KNOCKOUT_FRAMES_PER_TICK)
	assert_eq(plan.slow[301 + Director.KNOCKOUT_LINGER_TICKS - 1], Director.KNOCKOUT_FRAMES_PER_TICK)
	var knockout := Director.shot_for(plan.shots, 290)
	assert_eq(knockout.shot, Director.Shot.KNOCKOUT)
	assert_eq(knockout.side, 1, "the camera orbits the fighter who was knocked out")


func test_the_winner_gets_a_victory_shot_at_normal_speed() -> void:
	var plan := _plan()
	var start := 301 + Director.KNOCKOUT_LINGER_TICKS
	assert_eq(plan.victory, {"start": start, "side": 0})
	var victory := Director.shot_for(plan.shots, start)
	assert_eq(victory.shot, Director.Shot.VICTORY)
	assert_eq(victory.side, 0, "framing the winner")
	assert_eq(victory.end, plan.slow.size(), "to the end of the plan")
	assert_eq(plan.slow[start], 1, "slow motion ends with the knockout")


func test_no_victory_without_a_knockout() -> void:
	var events := _events().filter(func(e: Dictionary) -> bool: return e.type != "knockout")
	var plan := Director.plan(events, 301, MAX_HP, MOVE_POWER, SimRandom.new(1))
	assert_eq(plan.victory, {})
	assert_eq(plan.slow.size(), 301 + Director.KNOCKOUT_LINGER_TICKS)


func test_event_driven_shots() -> void:
	var plan := _plan()
	var tracking := Director.shot_for(plan.shots, 30)
	assert_eq(tracking.shot, Director.Shot.TRACKING, "a projectile in flight for 20 ticks")
	assert_eq(tracking.side, 0)
	var impact := Director.shot_for(plan.shots, 105)
	assert_eq(impact.shot, Director.Shot.IMPACT, "punch-in on the critical hit")
	assert_eq(impact.side, 0, "framing the defender")
	assert_true(Director.shot_for(plan.shots, 5).shot == Director.Shot.WIDE, "battles open wide")


func test_same_seed_same_edit_and_seed_changes_base_shots() -> void:
	assert_eq(_plan(1), _plan(1))
	var differs := false
	for seed in range(2, 10):
		if _plan(seed).shots != _plan(1).shots:
			differs = true
	assert_true(differs)


func test_frames_from_counts_holds() -> void:
	var plan := _plan()
	var total := Director.frames_from(plan, 0)
	assert_eq(total, Array(plan.slow).reduce(func(a, b): return a + b, 0) + Array(plan.hitstop).reduce(func(a, b): return a + b, 0))
	var victory: int = plan.victory.start
	assert_true(Director.frames_from(plan, 280) - Director.frames_from(plan, victory) > (victory - 280) * 2, "slow motion stretches the knockout")


func test_the_instant_replay_reshows_the_knockout_before_the_victory() -> void:
	var replay: Dictionary = _plan().replay
	assert_eq(replay.at, _plan().victory.start, "just before the victory")
	assert_eq(replay.knockout, 300)
	assert_eq(replay.start, 280, "from the finishing wind-up, which is under 24 ticks before")
	assert_eq(replay.end, 300 + Director.REPLAY_AFTER_TICKS + 1)
	assert_eq(replay.frames_per_tick, Director.REPLAY_FRAMES_PER_TICK)
	assert_true((replay.end - replay.start) * replay.frames_per_tick <= Director.REPLAY_MAX_FRAMES)
	var lead := Director.shot_for(replay.shots, 290)
	assert_eq([lead.shot, lead.side, lead.get("low", false)], [Director.Shot.OVER_SHOULDER, 0, true], "low behind the attacker")
	var hit := Director.shot_for(replay.shots, 300)
	assert_eq([hit.shot, hit.side], [Director.Shot.IMPACT, 1], "punch-in on the loser from the hit on")
	assert_eq(replay.shots[0].start, replay.start)
	assert_eq(replay.shots[-1].end, replay.end)


func test_a_long_windup_replays_only_the_last_ticks_before_the_knockout() -> void:
	var events := _events()
	events[4] = {"tick": 250, "type": "windup", "side": 0, "move": "cannon"}
	var replay: Dictionary = Director.plan(events, 301, MAX_HP, MOVE_POWER, SimRandom.new(1)).replay
	assert_eq(replay.start, 300 - Director.REPLAY_BEFORE_TICKS)


func test_no_replay_or_final_blow_without_a_knockout() -> void:
	var events := _events().filter(func(e: Dictionary) -> bool: return e.type != "knockout")
	var plan := Director.plan(events, 301, MAX_HP, MOVE_POWER, SimRandom.new(1))
	assert_eq(plan.replay, {})
	assert_eq(plan.captions, [])


func test_captions_mark_the_final_blow_and_each_fighters_first_comeback() -> void:
	var events := [
		{"tick": 10, "type": "hit", "side": 0, "move": "jet", "damage": 300, "crit": false, "effectiveness": 1.0, "hp": 100},
		{"tick": 50, "type": "hit", "side": 1, "move": "kick", "damage": 300, "crit": false, "effectiveness": 1.0, "hp": 100},
		{"tick": 60, "type": "hit", "side": 1, "move": "kick", "damage": 20, "crit": false, "effectiveness": 1.0, "hp": 80},
		{"tick": 70, "type": "hit", "side": 0, "move": "jet", "damage": 20, "crit": false, "effectiveness": 1.0, "hp": 80},
		{"tick": 280, "type": "windup", "side": 0, "move": "cannon"},
		{"tick": 300, "type": "hit", "side": 0, "move": "cannon", "damage": 80, "crit": false, "effectiveness": 1.0, "hp": 0},
		{"tick": 300, "type": "knockout", "side": 1},
	]
	var captions: Array = Director.plan(events, 301, MAX_HP, MOVE_POWER, SimRandom.new(1)).captions
	assert_eq(captions, [
		{"tick": 50, "text": Director.COMEBACK_CAPTION, "side": 1},
		{"tick": 70, "text": Director.COMEBACK_CAPTION, "side": 0},
		{"tick": 280, "text": Director.FINAL_BLOW_CAPTION, "side": 0},
	], "one comeback each, none on the finishing hit, then the final blow")


## Both fighters trade blows every half second, strong moves and heavy hits included.
func _busy_events() -> Array:
	var events: Array = []
	for i in 40:
		var tick := 20 + i * 15
		var side := i % 2
		events.append({"tick": tick, "type": "windup", "side": side, "move": "cannon" if side == 0 else "kick"})
		events.append({"tick": tick + 8, "type": "hit", "side": side, "move": "cannon" if side == 0 else "kick", "damage": 45 if i % 3 == 0 else 10,
			"crit": i % 7 == 0, "effectiveness": 1.0, "hp": 200})
	return events


func test_every_shot_holds_about_a_second() -> void:
	for seed in range(1, 6):
		var plan := Director.plan(_busy_events(), 640, MAX_HP, MOVE_POWER, SimRandom.new(seed))
		var shots: Array = plan.shots
		for i in range(0, shots.size() - 1):
			assert_true(shots[i].end - shots[i].start >= Director.MIN_SHOT_TICKS,
				"shot %d (%s) lasts %d ticks" % [i, Director.Shot.keys()[shots[i].shot], shots[i].end - shots[i].start])
		for i in range(1, shots.size()):
			assert_eq(shots[i].start, shots[i - 1].end, "shots are contiguous")


func test_a_close_up_arrives_as_the_move_goes_off() -> void:
	var events := [
		{"tick": 100, "type": "windup", "side": 1, "move": "cannon"},
		{"tick": 110, "type": "fire", "side": 1, "move": "cannon"},
	]
	var plan := Director.plan(events, 400, MAX_HP, [{}, {"cannon": 110}], SimRandom.new(1))
	var close_up := Director.shot_for(plan.shots, 100)
	assert_eq([close_up.shot, close_up.side], [Director.Shot.CLOSE_UP, 1])
	assert_eq([close_up.start, close_up.end], [110 - Director.CLOSE_UP_TICKS, 110], "a second before the release, ending on it")


func test_a_short_shot_gives_way_to_a_more_important_one() -> void:
	# A projectile in flight for 15 ticks, then a heavy hit: the tracking shot can't hold a
	# second before the punch-in, so the shot before it runs on into the punch-in.
	var events := [
		{"tick": 200, "type": "fire", "side": 0, "move": "jet"},
		{"tick": 215, "type": "hit", "side": 0, "move": "jet", "damage": 100, "crit": false, "effectiveness": 1.0, "hp": 300},
	]
	var plan := Director.plan(events, 400, MAX_HP, MOVE_POWER, SimRandom.new(1))
	var impact := Director.shot_for(plan.shots, 215)
	assert_eq([impact.shot, impact.start], [Director.Shot.IMPACT, 215], "the punch-in still lands on the hit")
	assert_true(Director.shot_for(plan.shots, 205).shot != Director.Shot.TRACKING, "the short tracking shot is dropped")


func test_close_ups_leave_room_between_them() -> void:
	var events := [
		{"tick": 100, "type": "windup", "side": 0, "move": "cannon"},
		{"tick": 110, "type": "fire", "side": 0, "move": "cannon"},
		{"tick": 130, "type": "windup", "side": 1, "move": "cannon"},
		{"tick": 140, "type": "fire", "side": 1, "move": "cannon"},
	]
	var power := [{"cannon": 110}, {"cannon": 110}]
	var plan := Director.plan(events, 400, MAX_HP, power, SimRandom.new(1))
	assert_eq(Director.shot_for(plan.shots, 105).shot, Director.Shot.CLOSE_UP)
	assert_true(Director.shot_for(plan.shots, 135).shot != Director.Shot.CLOSE_UP, "no second close-up straight after")


func test_every_knockout_gets_its_orbit_but_only_the_last_the_victory() -> void:
	var events := [
		{"tick": 90, "type": "windup", "side": 0, "move": "jet"},
		{"tick": 100, "type": "hit", "side": 0, "move": "jet", "damage": 200, "crit": false, "effectiveness": 1.0, "hp": 0,
			"slot": 0, "target_side": 1, "target_slot": 0},
		{"tick": 100, "type": "knockout", "side": 1, "slot": 0, "left": 1},
		{"tick": 160, "type": "send_out", "side": 1, "slot": 1},
		{"tick": 280, "type": "windup", "side": 0, "move": "cannon"},
		{"tick": 300, "type": "hit", "side": 0, "move": "cannon", "damage": 300, "crit": false, "effectiveness": 1.0, "hp": 0,
			"slot": 0, "target_side": 1, "target_slot": 1},
		{"tick": 300, "type": "knockout", "side": 1, "slot": 1, "left": 0},
	]
	var plan := Director.plan(events, 301, [[400], [200, 300]], MOVE_POWER, SimRandom.new(1))
	assert_eq(plan.slow[95], Director.KNOCKOUT_FRAMES_PER_TICK, "the first knockout plays in slow motion")
	assert_eq(plan.slow[100 + Director.KNOCKOUT_LINGER_TICKS + 5], 1, "then back to normal speed for the send-out")
	assert_eq(Director.shot_for(plan.shots, 100).shot, Director.Shot.KNOCKOUT)
	assert_eq(plan.victory.start, 301 + Director.KNOCKOUT_LINGER_TICKS, "the victory follows the last knockout")
	assert_eq(plan.replay.knockout, 300)
	assert_eq(plan.hitstop[300], Director.HEAVY_HITSTOP_FRAMES, "a heavy hit by the defender's own max HP")
