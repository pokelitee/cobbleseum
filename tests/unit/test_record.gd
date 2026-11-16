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


func test_credits_name_every_cc0_recording() -> void:
	var record: GDScript = load("res://tools/record.gd")
	var text: String = record.credits()
	assert_true(text.begins_with("Pokémon models"))
	assert_true(text.contains("GeneralUser GS"))
	for author in ["kyles", "FoolBoyMedia", "craigsmith", "benfree", "SamsterBirdies", "Fission9", "Spring Spring", "SketchMan3", "JaggedStone"]:
		assert_true(text.contains(" by %s (" % author), author)
