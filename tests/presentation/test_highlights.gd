extends TestCase

const MAX_HP := [400, 400]


func _hit(tick: int, side: int, damage: int, hp: int, crit := false, effectiveness := 1.0) -> Dictionary:
	return {"tick": tick, "type": "hit", "side": side, "move": "m", "damage": damage, "crit": crit,
		"effectiveness": effectiveness, "hp": hp}


## A flat plan: one frame per tick, no hit-stop.
func _plan(length: int) -> Dictionary:
	var slow := PackedInt32Array()
	slow.resize(length)
	slow.fill(1)
	var hitstop := PackedInt32Array()
	hitstop.resize(length)
	return {"slow": slow, "hitstop": hitstop}


func _frames(plan: Dictionary, window: Dictionary) -> int:
	var total := 0
	for t in range(window.start, window.end):
		total += plan.slow[t] + plan.hitstop[t]
	return total


func test_knockout_usually_ends_the_clip() -> void:
	var events := [_hit(100, 0, 40, 360), _hit(400, 1, 40, 360), _hit(800, 0, 360, 0), {"tick": 800, "type": "knockout", "side": 1}]
	var plan := _plan(830)
	var window := Highlights.choose(plan, events, MAX_HP, 150)
	assert_eq(window.end, 830, "ends where the plan ends")
	assert_true(_frames(plan, window) >= 150)


func test_a_flurry_beats_a_dull_finish() -> void:
	var events := []
	for i in 4:
		events.append(_hit(100 + 20 * i, i % 2, 90, 400 - 90 * (i / 2 + 1), true, 2.0))
	events.append(_hit(1000, 0, 40, 0))
	events.append({"tick": 1000, "type": "time_up", "side": -1})
	var window := Highlights.choose(_plan(1030), events, MAX_HP, 90)
	assert_eq(window.end, 160 + 1 + Highlights.END_LINGER_TICKS, "ends a linger after the flurry's last hit")
	assert_true(window.start <= 100, "starts before the flurry")


func test_windows_count_hitstop_and_slow_motion() -> void:
	var plan := _plan(300)
	for t in range(250, 300):
		plan.slow[t] = 3
	plan.hitstop[260] = 5
	var events := [_hit(260, 0, 400, 0), {"tick": 260, "type": "knockout", "side": 1}]
	var window := Highlights.choose(plan, events, MAX_HP, 200)
	assert_eq(window.end, 300)
	assert_eq(window.start, 300 - 50 - (200 - 155), "the slowed tail fills 155 frames, the rest at one per tick")


func test_short_battles_play_whole() -> void:
	var window := Highlights.choose(_plan(60), [_hit(30, 0, 400, 0)], MAX_HP, 300)
	assert_eq(window.start, 0)
	assert_eq(window.end, 60)


func test_comebacks_and_crits_score_higher() -> void:
	var events := [_hit(10, 0, 300, 100), _hit(20, 1, 40, 360), _hit(30, 1, 40, 320, true, 2.0)]
	var scores := Highlights.event_scores(events, MAX_HP)
	assert_almost_eq(scores[0], 1.0 + 4.0 * 0.75, 1e-5)
	assert_almost_eq(scores[1], 1.0 + 0.4 + Highlights.COMEBACK_SCORE, 1e-5, "side 1 hits back from 25% HP")
	assert_almost_eq(scores[2], 1.0 + 0.4 + 1.0 + 1.0 + Highlights.COMEBACK_SCORE, 1e-5)


func test_windows_never_cut_the_knockout_short() -> void:
	var events := [_hit(500, 0, 200, 200), _hit(520, 1, 200, 200), _hit(800, 0, 200, 0),
		{"tick": 800, "type": "knockout", "side": 1}]
	var window := Highlights.choose(_plan(830), events, MAX_HP, 330)
	assert_eq(window.end, 830, "a window holding the knockout plays to the plan's end")


func test_the_victory_comes_on_top_of_the_clip() -> void:
	var events := [_hit(500, 0, 300, 100), _hit(520, 0, 50, 50), _hit(800, 0, 50, 0),
		{"tick": 800, "type": "knockout", "side": 1}]
	var plan := _plan(905)
	plan.victory = {"start": 830, "side": 0}
	var window := Highlights.choose(plan, events, MAX_HP, 330)
	assert_eq(window.end, 905, "the knockout and then the whole victory")
	assert_true(_frames(plan, window) >= 330 + 75, "the victory doesn't eat into the action")
