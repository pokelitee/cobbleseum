extends TestCase

const OPTIONS: Array[String] = ["effect", "on", "at", "aim", "aim_at", "delay", "max", "keep", "face_camera", "tint",
	"speed", "scale"]


## Every committed sequence loads, and its pieces use only known locators and options, so a
## typo shows up here rather than as a silently missing effect in a clip.
func test_every_sequence_is_well_formed() -> void:
	var files := DirAccess.get_files_at(MoveSequence.DIR)
	var count := 0
	for file in files:
		if not file.ends_with(".gd"):
			continue
		count += 1
		var id := file.get_basename()
		var sequence := MoveSequence.for_move(id)
		assert_true(sequence != null, "%s is a MoveSequence" % id)
		if sequence == null:
			continue
		assert_true(sequence.speed() > 0.0, "%s has a positive speed" % id)
		var pieces := 0
		for phase in MoveSequence.PHASES:
			for piece: Dictionary in sequence.steps_for(phase):
				pieces += 1
				assert_true(not str(piece.effect).is_empty(), "%s %s names an effect" % [id, phase])
				assert_true(SequenceSteps.LOCATORS.has(piece.at), "%s %s: unknown locator %s" % [id, phase, piece.at])
				if piece.has("aim_at"):
					assert_true(SequenceSteps.LOCATORS.has(piece.aim_at), "%s %s: unknown aim locator %s" % [id, phase, piece.aim_at])
				for key: String in piece:
					assert_true(OPTIONS.has(key), "%s %s: unknown option %s" % [id, phase, key])
		assert_true(pieces > 0, "%s plays something" % id)
	assert_true(count > 0, "sequences exist")


func test_moves_without_a_sequence_have_none() -> void:
	assert_eq(MoveSequence.for_move("no_such_move"), null)
