extends TestCase
## The balance report's arithmetic (tools/batch.gd) and the overtime rule it tuned.

const Batch := preload("res://tools/batch.gd")


func _row(result: String, seconds: float, advantage: int, kinds := {}) -> Dictionary:
	return {"result": result, "seconds": seconds, "advantage": advantage, "kinds": kinds, "events": {"hit": 10}}


func test_summary_counts_length_draws_and_advantage() -> void:
	var rows: Array[Dictionary] = [
		_row("WIN_A", 20.0, 0, {"melee": 3}),
		_row("WIN_B", 30.0, 0, {"projectile": 1}),
		_row("WIN_B", 40.0, 1),
		_row("DRAW", 90.0, -1),
	]
	var report := Batch.summarise(rows)
	assert_eq(report.battles, 4)
	assert_eq(report.median_seconds, 40.0, "the middle value of 4, rounded up")
	assert_eq(report.draw_rate, 0.25)
	assert_almost_eq(report.side_a_win_rate, 1.0 / 3.0, 1e-6)
	assert_almost_eq(report.advantage_win_rate, 2.0 / 3.0, 1e-6, "side 0 won once of twice, side 1 once of once")
	assert_eq(report.move_kind_shares, {"melee": 0.75, "projectile": 0.25})
	assert_eq(report.per_battle.hit, 10.0)


func test_overtime_ramps_damage_after_its_start() -> void:
	assert_eq(Rules.overtime_factor(0), 1.0)
	assert_eq(Rules.overtime_factor(Rules.seconds_to_ticks(Rules.OVERTIME_SECONDS)), 1.0)
	var at_cap := Rules.overtime_factor(Rules.seconds_to_ticks(Rules.TIME_CAP_SECONDS))
	assert_almost_eq(at_cap, 1.0 + Rules.OVERTIME_RAMP * (Rules.TIME_CAP_SECONDS - Rules.OVERTIME_SECONDS), 1e-6)
