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
		{"tick": 300, "type": "faint", "side": 1},
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
	assert_eq(knockout.side, 1, "the camera orbits the fighter who fainted")


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
	var events := _events().filter(func(e: Dictionary) -> bool: return e.type != "faint")
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
