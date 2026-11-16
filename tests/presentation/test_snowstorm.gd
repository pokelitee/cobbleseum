extends TestCase
## The native move-effect runtime (game/native, built by tools/native/build.sh): Molang,
## curves, colours and an emitter running a small effect. The classes are looked up by name
## so this file loads, and fails clearly, when the extension isn't built.


func _native(name: String) -> bool:
	var found := ClassDB.class_exists(name)
	assert_true(found, "%s exists; build the extension with tools/native/build.sh" % name)
	return found


func _evaluate(source: String, v := {}, q := {}, seed_value := 1) -> Dictionary:
	return ClassDB.class_call_static("SnowstormProgram", "evaluate", source, v, q, seed_value)


func _value(source: String, v := {}, q := {}) -> float:
	var result := _evaluate(source, v, q)
	assert_eq(result.error, "", "compiles %s" % source)
	return float(result.value)


func test_numbers_and_arithmetic() -> void:
	if not _native("SnowstormProgram"):
		return
	assert_almost_eq(_value("2.5"), 2.5, 0.0001)
	assert_almost_eq(_value("1/2 + 3*2"), 6.5, 0.0001, "integer literals divide as floats")
	assert_almost_eq(_value("-(2 - 5)"), 3.0, 0.0001)


func test_names_read_variables_and_queries() -> void:
	if not _native("SnowstormProgram"):
		return
	assert_almost_eq(_value("v.a + variable.a + q.entity_height", {"a": 2.0}, {"entity_height": 1.5}), 5.5, 0.0001)
	assert_almost_eq(_value("v.unset * 3"), 0.0, 0.0001, "unset variables read as 0")


func test_math_uses_degrees() -> void:
	if not _native("SnowstormProgram"):
		return
	assert_almost_eq(_value("math.sin(90)"), 1.0, 0.0001)
	assert_almost_eq(_value("math.clamp(v.x, 1, 7)", {"x": 10.0}), 7.0, 0.0001)


func test_comparisons_logic_and_ternary() -> void:
	if not _native("SnowstormProgram"):
		return
	assert_almost_eq(_value("v.a < 3 ? 0.2 : 0.175", {"a": 1.0}), 0.2, 0.0001)
	assert_almost_eq(_value("(v.a > 1 && v.a < 3) * 4", {"a": 2.0}), 4.0, 0.0001, "comparisons are numbers")
	assert_almost_eq(_value("!v.a || 0", {"a": 0.0}), 1.0, 0.0001)


func test_statements_assign_and_return() -> void:
	if not _native("SnowstormProgram"):
		return
	var result := _evaluate("v.target_deltaz=5;v.target_distance=3.5;")
	assert_almost_eq(float(result.value), 3.5, 0.0001)
	assert_almost_eq(float(result.v.target_deltaz), 5.0, 0.0001, "assignments write the variables")
	assert_almost_eq(_value("v.x = 2; return v.x * 3; 99"), 6.0, 0.0001)


func test_random_is_seeded() -> void:
	if not _native("SnowstormProgram"):
		return
	var first := _evaluate("math.random(0, 10)", {}, {}, 42)
	var second := _evaluate("math.random(0, 10)", {}, {}, 42)
	assert_eq(first.value, second.value, "same seed, same draw")
	assert_true(float(first.value) >= 0.0 and float(first.value) <= 10.0)
	var unit := _value("math.random()")
	assert_true(unit >= 0.0 and unit < 1.0, "math.random() with no range draws from [0, 1)")


func test_unsupported_text_is_rejected_not_run() -> void:
	if not _native("SnowstormProgram"):
		return
	for source in ["OS.get_name()", "v.a; q.b.c", "math.nope(1)", "\"text\"", "math.max(1, 2, 3)", "(1 + 2"]:
		var result := _evaluate(source)
		assert_true(not str(result.error).is_empty(), "%s is rejected" % source)
		assert_almost_eq(float(result.value), 0.0, 0.0001)


func test_curves() -> void:
	if not _native("SnowstormProgram"):
		return
	var program: RefCounted = ClassDB.instantiate("SnowstormProgram")
	var error: String = program.parse({"particle_effect": {"curves": {"variable.fade": {
		"type": "linear", "input": "v.particle_age", "horizontal_range": "v.particle_lifetime", "nodes": [0, 1, 0]}}}})
	assert_eq(error, "")
	assert_almost_eq(program.curve_at(0.25, 1.0), 0.5, 0.0001)
	assert_almost_eq(program.curve_at(0.5, 1.0), 1.0, 0.0001)


func test_bedrock_colours_are_argb() -> void:
	if not _native("SnowstormProgram"):
		return
	var colour: Color = ClassDB.class_call_static("SnowstormProgram", "parse_colour", "#80FF0000")
	assert_almost_eq(colour.r, 1.0, 0.01)
	assert_almost_eq(colour.a, 0.5, 0.01, "alpha comes first")


func test_an_emitter_runs_and_ends() -> void:
	if not _native("SnowstormCore"):
		return
	var program: RefCounted = ClassDB.instantiate("SnowstormProgram")
	assert_eq(program.parse({"particle_effect": {"description": {"identifier": "test:burst"}, "components": {
		"minecraft:emitter_lifetime_once": {"active_time": 0.1},
		"minecraft:emitter_rate_instant": {"num_particles": 5},
		"minecraft:emitter_shape_sphere": {"radius": 0.5},
		"minecraft:particle_lifetime_expression": {"max_lifetime": 0.5},
		"minecraft:particle_initial_speed": "v.target_distance",
		"minecraft:particle_appearance_billboard": {"size": [0.2, 0.2], "facing_camera_mode": "rotate_xyz"},
	}}}), "")
	var runs: Array = []
	for attempt in 2:
		var core: RefCounted = ClassDB.instantiate("SnowstormCore")
		core.start(program, Transform3D.IDENTITY, 7, {"target_distance": 2.0}, {}, 1.0, 1.0)
		core.step(1.0 / 30.0, Basis.IDENTITY, Vector3(0, 0, 5), 0.0)
		assert_eq(core.get_drawn(), 5, "the burst is drawn")
		runs.append(core.get_buffer())
		for i in 30:
			core.step(1.0 / 30.0, Basis.IDENTITY, Vector3(0, 0, 5), 0.0)
		assert_true(core.is_finished(), "and ends once its particles die")
	assert_eq(runs[0], runs[1], "the same seed draws the same particles")


func test_target_variables_follow_cobblemon_convention() -> void:
	var from := Transform3D(Basis.looking_at(Vector3.RIGHT, Vector3.UP), Vector3(0, 1, 0))
	var vars := CobblemonMoveFX.target_vars(from, Transform3D(Basis.IDENTITY, Vector3(4, 2, 0)))
	assert_almost_eq(vars.target_deltaz, 4.0, 0.0001, "a target straight ahead is +deltaz")
	assert_almost_eq(vars.target_deltay, 1.0, 0.0001)
	assert_almost_eq(vars.target_deltax, 0.0, 0.0001)
	assert_almost_eq(vars.target_distance, sqrt(17.0), 0.0001)
