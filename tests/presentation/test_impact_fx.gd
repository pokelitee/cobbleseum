extends TestCase


func _run_effects() -> Array:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var camera := Camera3D.new()
	root.add_child(camera)
	var defender := FighterView.new()
	defender.height = 2.0
	root.add_child(defender)
	var fx := ImpactFX.new()
	root.add_child(fx)
	fx.setup(camera, Vector2(1920, 1080), Vector2(170, 80))
	fx.on_hit({"damage": 40, "crit": true, "effectiveness": 1.3}, defender, 0.1, true)
	var offsets: Array = []
	for i in ImpactFX.SHAKE_FRAMES + 2:
		fx.next_frame()
		offsets.append(Vector2(camera.h_offset, camera.v_offset))
	var callouts := fx.get_children().filter(func(n: Node) -> bool: return n is Label).size()
	for node in [fx, defender, camera]:
		node.free()
	return [offsets, callouts]


func test_shake_is_frame_based_and_settles() -> void:
	var first := _run_effects()
	var second := _run_effects()
	assert_eq(first[0], second[0], "same frames, same shake")
	assert_true((first[0][0] as Vector2).length() > 0.0)
	assert_eq(first[0][-1], Vector2.ZERO, "shake ends after SHAKE_FRAMES")


func test_big_hit_shows_damage_crit_and_effectiveness() -> void:
	assert_eq(_run_effects()[1], 3)


func test_speed_lines_fade_in_and_out() -> void:
	var camera := Camera3D.new()
	var fx := ImpactFX.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(fx)
	fx.setup(camera, Vector2(1920, 1080), Vector2(170, 80))
	for i in 3:
		fx.set_speed_lines(true)
	assert_almost_eq(fx._speed_lines.material.get_shader_parameter("intensity"), 0.6, 1e-6)
	fx.set_speed_lines(false)
	assert_almost_eq(fx._speed_lines.material.get_shader_parameter("intensity"), 0.4, 1e-6)
	fx.free()
	camera.free()


func test_a_cut_flash_whites_out_then_fades() -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var camera := Camera3D.new()
	root.add_child(camera)
	var fx := ImpactFX.new()
	root.add_child(fx)
	fx.setup(camera, Vector2(1920, 1080), Vector2(170, 80))
	var view := FighterView.new()
	root.add_child(view)
	fx.announce(view, "Must recharge!", Color.WHITE)
	fx.cut_flash()
	assert_eq(fx._callouts, [], "callouts end at the cut")
	var alphas: Array = []
	for i in ImpactFX.CUT_FLASH_FRAMES + 1:
		fx.next_frame()
		alphas.append(fx._flash.color.a)
	assert_eq(alphas[0], 1.0, "white on the cut")
	for i in range(1, alphas.size()):
		assert_true(alphas[i] < alphas[i - 1], "fading")
	assert_eq(alphas[-1], 0.0)
	for node in [fx, view, camera]:
		node.free()
