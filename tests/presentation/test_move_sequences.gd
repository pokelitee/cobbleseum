extends TestCase

const OPTIONS: Array[String] = ["effect", "on", "at", "aim", "aim_at", "delay", "max", "keep", "face_camera", "tint", "nudge",
	"speed", "scale"]


## Every committed sequence, the moves' own and the styles', loads, and its pieces use only
## known locators and options, so a typo shows up here rather than as a silently missing
## effect in a clip.
func test_every_sequence_is_well_formed() -> void:
	var count := 0
	for dir in [MoveSequence.DIR, MoveSequence.STYLES_DIR]:
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".gd"):
				continue
			count += 1
			var id := file.get_basename()
			var sequence := MoveSequence.load_from(dir, id)
			assert_true(sequence != null, "%s is a MoveSequence" % id)
			if sequence == null:
				continue
			assert_true(sequence.speed() > 0.0, "%s has a positive speed" % id)
			var pieces := 0
			for phase in MoveSequence.PHASES:
				for piece: Dictionary in sequence.steps_for(phase, "Fire"):
					pieces += 1
					assert_true(not str(piece.effect).is_empty(), "%s %s names an effect" % [id, phase])
					assert_true(SequenceSteps.LOCATORS.has(piece.at), "%s %s: unknown locator %s" % [id, phase, piece.at])
					if piece.has("aim_at"):
						assert_true(SequenceSteps.LOCATORS.has(piece.aim_at), "%s %s: unknown aim locator %s" % [id, phase, piece.aim_at])
					for key: String in piece:
						assert_true(OPTIONS.has(key), "%s %s: unknown option %s" % [id, phase, key])
			assert_true(pieces > 0, "%s plays something" % id)
	assert_true(count > 0, "sequences exist")


## Every move without a sequence of its own falls back to its style's, so every style needs one.
func test_every_style_has_a_sequence() -> void:
	for style: String in MoveStyle.MELEE + MoveStyle.RANGED + ["status"]:
		var sequence := MoveSequence.load_from(MoveSequence.STYLES_DIR, style)
		assert_true(sequence is StyleSequence, "%s has a style sequence" % style)


func test_damaging_styles_hit_and_blast_in_the_type_colour() -> void:
	for style: String in MoveStyle.MELEE + MoveStyle.RANGED:
		var sequence := MoveSequence.load_from(MoveSequence.STYLES_DIR, style)
		var hit := sequence.steps_for("hit", "Water").map(func(piece: Dictionary) -> String: return piece.effect)
		assert_true(hit.has("impact_water"), "%s hits with the type's impact" % style)
		assert_true(not sequence.steps_for("blast", "Water").is_empty(), "%s has an area version" % style)


func test_types_without_an_impact_use_normal() -> void:
	var steps := SequenceSteps.new()
	steps.type = "stellar"
	steps.impact()
	assert_eq(steps.pieces[0].effect, "impact_normal")


func test_moves_without_a_sequence_have_none() -> void:
	assert_eq(MoveSequence.for_move("no_such_move"), null)
