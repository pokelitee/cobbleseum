class_name TestCase
extends RefCounted
## Base class for tests. Test scripts extend it and define methods named test_*.

var failures: PackedStringArray = []
## Logged errors this test causes on purpose; the runner ignores that many.
var expected_errors := 0


func assert_true(condition: bool, message := "") -> void:
	if not condition:
		_fail("expected true", message)


func assert_false(condition: bool, message := "") -> void:
	if condition:
		_fail("expected false", message)


## Strict equality: values of different types never match, so 1 and 1.0 differ.
func assert_eq(actual: Variant, expected: Variant, message := "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		_fail("expected %s, got %s" % [var_to_str(expected), var_to_str(actual)], message)


func assert_almost_eq(actual: float, expected: float, tolerance: float, message := "") -> void:
	if absf(actual - expected) > tolerance:
		_fail("expected %s ± %s, got %s" % [expected, tolerance, actual], message)


func fail(message: String) -> void:
	_fail("failed", message)


func _fail(reason: String, message: String) -> void:
	failures.append(reason if message.is_empty() else "%s: %s" % [message, reason])
