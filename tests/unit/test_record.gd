extends TestCase
## tools/record.gd: when a render's output can be used.

const RECORD := preload("res://tools/record.gd")


func test_a_render_must_verify_and_log_no_script_errors() -> void:
	var ok := "frames...
%s abc
" % BattleView.CHECKSUM_OK
	assert_eq(RECORD.render_problem(ok, 0, "abc"), "")
	assert_eq(RECORD.render_problem(ok, 1, "abc"), "failed")
	assert_eq(RECORD.render_problem(ok, 0, "def"), "didn't verify", "another battle's checksum")
	assert_eq(RECORD.render_problem("SCRIPT ERROR: Nil
" + ok, 0, "abc"), "logged script errors")
