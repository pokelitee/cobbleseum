extends TestCase


func test_assert_eq_accepts_equal_values() -> void:
	var probe := TestCase.new()
	probe.assert_eq(3, 3)
	probe.assert_eq("a", "a")
	assert_true(probe.failures.is_empty())


func test_assert_eq_rejects_different_values() -> void:
	var probe := TestCase.new()
	probe.assert_eq(3, 4, "values")
	assert_eq(probe.failures.size(), 1)
	assert_true(probe.failures[0].begins_with("values: "))


func test_assert_eq_rejects_type_mismatch() -> void:
	var probe := TestCase.new()
	probe.assert_eq(1, 1.0)
	assert_eq(probe.failures.size(), 1)


func test_assert_almost_eq_uses_tolerance() -> void:
	var probe := TestCase.new()
	probe.assert_almost_eq(1.0, 1.05, 0.1)
	assert_true(probe.failures.is_empty())
	probe.assert_almost_eq(1.0, 1.2, 0.1)
	assert_eq(probe.failures.size(), 1)
