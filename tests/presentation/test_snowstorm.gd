extends TestCase


func _run(source: Variant, v := {}, q := {}) -> float:
	var program := ParticleMolang.compile(source)
	assert_eq(program.error, "", "compiles %s" % str(source))
	for key: String in program.names:
		var name := key.substr(2)
		if key.begins_with("v.") and not v.has(name):
			v[name] = 0.0
		elif key.begins_with("q.") and not q.has(name):
			q[name] = 0.0
	return program.evaluate(v, q, ParticleMath.new())


func test_numbers_and_arithmetic() -> void:
	assert_almost_eq(_run(2.5), 2.5, 0.0001)
	assert_almost_eq(_run("1/2 + 3*2"), 6.5, 0.0001, "integer literals divide as floats")
	assert_almost_eq(_run("-(2 - 5)"), 3.0, 0.0001)


func test_names_read_variables_and_queries() -> void:
	assert_almost_eq(_run("v.a + variable.a + q.entity_height", {"a": 2.0}, {"entity_height": 1.5}), 5.5, 0.0001)
	assert_almost_eq(_run("v.unset * 3"), 0.0, 0.0001, "unset variables read as 0")


func test_math_uses_degrees() -> void:
	assert_almost_eq(_run("math.sin(90)"), 1.0, 0.0001)
	assert_almost_eq(_run("math.clamp(v.x, 1, 7)", {"x": 10.0}), 7.0, 0.0001)


func test_comparisons_logic_and_ternary() -> void:
	assert_almost_eq(_run("v.a < 3 ? 0.2 : 0.175", {"a": 1.0}), 0.2, 0.0001)
	assert_almost_eq(_run("(v.a > 1 && v.a < 3) * 4", {"a": 2.0}), 4.0, 0.0001, "comparisons are numbers")
	assert_almost_eq(_run("!v.a || 0", {"a": 0.0}), 1.0, 0.0001)


func test_statements_assign_and_return() -> void:
	var v := {}
	assert_almost_eq(_run("v.target_deltaz=5;v.target_distance=3.5;", v), 3.5, 0.0001)
	assert_almost_eq(float(v.target_deltaz), 5.0, 0.0001, "assignments write the variables")
	assert_almost_eq(_run("v.x = 2; return v.x * 3; 99"), 6.0, 0.0001)


func test_random_is_seeded() -> void:
	var first := ParticleMath.new()
	var second := ParticleMath.new()
	first.rng.seed = 42
	second.rng.seed = 42
	var program := ParticleMolang.compile("math.random(0, 10)")
	assert_eq(program.evaluate({}, {}, first), program.evaluate({}, {}, second), "same seed, same draw")


func test_unsupported_text_is_rejected_not_run() -> void:
	for source in ["OS.get_name()", "v.a; q.b.c", "math.nope(1)", "\"text\""]:
		var program := ParticleMolang.compile(source)
		assert_true(not program.error.is_empty(), "%s is rejected" % source)
		assert_almost_eq(program.evaluate({}, {}, ParticleMath.new()), 0.0, 0.0001)


func test_curves() -> void:
	var effect := SnowstormEffect.parse({"particle_effect": {"curves": {"variable.fade": {
		"type": "linear", "input": "v.particle_age", "horizontal_range": "v.particle_lifetime", "nodes": [0, 1, 0]}}}})
	var v := {"particle_age": 0.25, "particle_lifetime": 1.0, "fade": 0.0}
	assert_almost_eq(effect.curve_value(effect.curves.fade, v, {}, ParticleMath.new()), 0.5, 0.0001)
	v.particle_age = 0.5
	assert_almost_eq(effect.curve_value(effect.curves.fade, v, {}, ParticleMath.new()), 1.0, 0.0001)


func test_bedrock_colours_are_argb() -> void:
	var colour := SnowstormEmitter._hex("#80FF0000")
	assert_almost_eq(colour.r, 1.0, 0.01)
	assert_almost_eq(colour.a, 0.5, 0.01, "alpha comes first")


func test_target_variables_follow_cobblemon_convention() -> void:
	var from := Transform3D(Basis.looking_at(Vector3.RIGHT, Vector3.UP), Vector3(0, 1, 0))
	var vars := CobblemonMoveFX.target_vars(from, Transform3D(Basis.IDENTITY, Vector3(4, 2, 0)))
	assert_almost_eq(vars.target_deltaz, 4.0, 0.0001, "a target straight ahead is +deltaz")
	assert_almost_eq(vars.target_deltay, 1.0, 0.0001)
	assert_almost_eq(vars.target_deltax, 0.0, 0.0001)
	assert_almost_eq(vars.target_distance, sqrt(17.0), 0.0001)
