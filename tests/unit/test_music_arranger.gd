extends TestCase

const SCORES := ["clash", "overdrive", "summit"]


func _score(id: String) -> Dictionary:
	var loaded := MusicArranger.load_score("res://tools/music/scores/%s.json" % id)
	assert_false(loaded.has("error"), str(loaded.get("error", "")))
	return loaded.get("score", {})


func test_every_committed_score_loads() -> void:
	for id in SCORES + ["victory"]:
		_score(id)


func test_build_lists_every_score_as_a_dependency() -> void:
	var build: GDScript = load("res://tools/sources/music.gd")
	var constants := build.get_script_constant_map()
	for id: String in constants.TRACKS + [constants.STING]:
		assert_true("res://tools/music/scores/%s.json" % id in constants.DEPENDENCIES, id)


func test_tracks_fill_every_layer_and_play_the_loop_twice() -> void:
	for id in SCORES:
		var arranged := MusicArranger.new().arrange(_score(id))
		var layers := {}
		for note: Dictionary in arranged.notes:
			layers[note.layer] = true
		for layer in MusicArranger.LAYERS:
			assert_true(layers.has(layer), "%s has no %s" % [id, layer])
		var bar := MusicArranger.STEPS_PER_BAR
		var loop := 3 * MusicArranger.SECTION_BARS * bar
		assert_eq(arranged.intro_end, MusicArranger.INTRO_BARS * bar, id)
		assert_eq(arranged.loop_start, arranged.intro_end + loop, "the loop kept is the second pass")
		assert_eq(arranged.loop_end, arranged.loop_start + loop, id)


func test_arranging_is_repeatable() -> void:
	var score := _score("clash")
	assert_eq(MusicArranger.new().arrange(score), MusicArranger.new().arrange(score))


func test_the_lead_variants_differ_only_in_the_main_lead() -> void:
	var notes: Array = MusicArranger.new().arrange(_score("clash")).notes
	var programs := [{}, {}]
	for note: Dictionary in notes:
		if note.layer.begins_with("lead_"):
			programs[int(note.layer.right(1))][note.program] = true
	assert_true(programs[0].has(81) and not programs[0].has(80), "variant 0 leads on the saw")
	assert_true(programs[1].has(80) and not programs[1].has(81), "variant 1 leads on the square")


func test_notes_and_lines() -> void:
	assert_eq(MusicArranger.midi("C4"), 60)
	assert_eq(MusicArranger.midi("C#5"), 73)
	assert_eq(MusicArranger.midi("Bb4"), 70)
	assert_eq(MusicArranger.midi("H4"), -1)
	assert_eq(MusicArranger.line_length("D5:6 A4:2 r:8"), 16)
	assert_eq(MusicArranger.line_length("D5:x"), -1)
	assert_eq(MusicArranger.line_length(""), 0)


func test_thirds_below_stay_in_the_scale() -> void:
	var d_minor := [2, 4, 5, 7, 9, 10, 0]
	assert_eq(MusicArranger.third_below(77, d_minor), 74, "F to D")
	assert_eq(MusicArranger.third_below(74, d_minor), 70, "D to B flat")
	assert_eq(MusicArranger.third_below(73, d_minor), 69, "C sharp, outside the scale, to A")


func test_bass_roots_sit_low() -> void:
	assert_eq(MusicArranger.bass_root([62, 65, 69]), 38, "D minor on D2")
	assert_eq(MusicArranger.bass_root([57, 61, 64]), 33, "A major on A1")
	assert_eq(MusicArranger.bass_root([55, 59, 62]), 31, "G major on G1")


func test_problems_are_reported() -> void:
	var score := _score("clash")
	assert_eq(MusicArranger.problem(score), "")
	var short_bar := score.duplicate(true)
	short_bar.sections[0].chords[0] = [["Dm", 12]]
	assert_true(MusicArranger.problem(short_bar).contains("12 steps"))
	var unknown := score.duplicate(true)
	unknown.sections[1].chords[2] = [["Zz", 16]]
	assert_true(MusicArranger.problem(unknown).contains("unknown chord"))
	var long_line := score.duplicate(true)
	long_line.sections[0].melody[0] = "D5:20"
	assert_true(MusicArranger.problem(long_line).contains("20 steps"))
	assert_true(MusicArranger.problem({"title": "x"}).contains("missing"))
	var bad_eq := score.duplicate(true)
	bad_eq.eq = [{"type": "notch", "hz": 300.0}]
	assert_true(MusicArranger.problem(bad_eq).contains("eq"))


func test_the_sting_arranges_every_part() -> void:
	var score := _score("victory")
	var notes := MusicArranger.new().arrange_once(score)
	var programs := {}
	for note in notes:
		programs[note.program] = true
		assert_eq(note.layer, "once")
	assert_true(programs.has(56) and programs.has(61), "trumpets and brass")
