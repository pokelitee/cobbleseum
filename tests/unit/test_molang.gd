extends TestCase


func _eval(text: String, t := 0.0) -> float:
	var expression := Molang.compile(text)
	assert_eq(expression.error, "", text)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	return expression.evaluate(t, rng)


func test_arithmetic_and_precedence() -> void:
	assert_almost_eq(_eval("1 + 2 * 3"), 7.0, 1e-9)
	assert_almost_eq(_eval("(1 + 2) * 3"), 9.0, 1e-9)
	assert_almost_eq(_eval("8 / 4 / 2"), 1.0, 1e-9)
	assert_almost_eq(_eval("10 - 4 - 3"), 3.0, 1e-9)
	assert_almost_eq(_eval("-2 * -3"), 6.0, 1e-9)
	assert_almost_eq(_eval(".5 + 0.25"), 0.75, 1e-9)


func test_division_by_zero_is_zero() -> void:
	assert_eq(_eval("1 / 0"), 0.0)


func test_trigonometry_uses_degrees() -> void:
	assert_almost_eq(_eval("math.sin(90)"), 1.0, 1e-9)
	assert_almost_eq(_eval("math.cos(180)"), -1.0, 1e-9)
	assert_almost_eq(_eval("math.atan2(1, 1)"), 45.0, 1e-9)


func test_animation_time_names() -> void:
	assert_almost_eq(_eval("q.anim_time * 2", 1.5), 3.0, 1e-9)
	assert_almost_eq(_eval("Query.Anim_Time", 0.25), 0.25, 1e-9)


func test_real_expression_with_not() -> void:
	# From a Cobblemon animation: "+!0" adds 1.
	assert_almost_eq(_eval("4.799+2.5*math.sin((q.anim_time*90*4)+!0)", 0.0), 4.799 + 2.5 * sin(deg_to_rad(1.0)), 1e-9)


func test_math_functions() -> void:
	assert_eq(_eval("math.clamp(5, 0, 2)"), 2.0)
	assert_eq(_eval("math.mod(-7, 3)"), -1.0)
	assert_eq(_eval("math.round(2.5)"), 3.0)
	assert_eq(_eval("math.trunc(-2.7)"), -2.0)
	assert_almost_eq(_eval("math.lerp(0, 10, 0.25)"), 2.5, 1e-9)
	assert_almost_eq(_eval("math.pi"), PI, 1e-9)


func test_random_is_seeded_and_in_range() -> void:
	var a := _eval("math.random(-0.1, 0.1)")
	assert_eq(_eval("math.random(-0.1, 0.1)"), a, "same seed, same value")
	assert_true(a >= -0.1 and a <= 0.1)
	var n := _eval("math.random_integer(1, 3)")
	assert_true(n == 1.0 or n == 2.0 or n == 3.0)


func test_unknown_names_are_zero_and_reported() -> void:
	var expression := Molang.compile("math.clamp(q.r.pitch_change(0), -0.5, 1.0) * -20 + 1")
	assert_eq(expression.error, "")
	assert_eq(expression.unknown_names, PackedStringArray(["q.r.pitch_change"]))
	assert_eq(expression.evaluate(0.0, RandomNumberGenerator.new()), 1.0)
	var names := Molang.compile("v.foot * 2 + q.anim_time")
	assert_eq(names.error, "")
	assert_eq(names.unknown_names, PackedStringArray(["v.foot"]))
	assert_eq(names.evaluate(3.0, RandomNumberGenerator.new()), 3.0)


func test_parse_errors_evaluate_to_zero() -> void:
	for text in ["(1 + 2", "1 +", "1 2", "math.sin(1, 2)", "a == b", "math.s(1)"]:
		var expression := Molang.compile(text)
		assert_false(expression.error.is_empty(), text)
		assert_eq(expression.evaluate(0.0, RandomNumberGenerator.new()), 0.0, text)
