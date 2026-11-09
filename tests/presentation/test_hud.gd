extends TestCase


func _hud(size := Vector2(1920, 1080)) -> Hud:
	var hud := Hud.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	hud.setup(["Left", "Right"], size)
	return hud


func test_lag_segment_holds_then_drains_to_the_bar() -> void:
	for side in 2:
		var hud := _hud()
		hud.set_hp(side, 0.5, true)
		hud.set_hp(side, 0.0)
		for i in Hud.LAG_DELAY:
			hud.set_hp(side, 0.0)
			hud.next_frame()
		assert_almost_eq(hud._lags[side].scale.x, 0.5, 1e-6, "side %d holds during the delay" % side)
		for i in 60:
			hud.set_hp(side, 0.0)
			hud.next_frame()
		# A Control scale bottoms out at 1e-5, never exactly 0.
		assert_almost_eq(hud._lags[side].scale.x, 0.0, 1e-4, "side %d drains to the bar" % side)
		hud.free()


func test_bar_colour_follows_health() -> void:
	var hud := _hud()
	hud.set_hp(0, 0.8)
	assert_eq(hud._bars[0].color, Hud.HEALTHY)
	hud.set_hp(0, 0.4)
	assert_eq(hud._bars[0].color, Hud.WARNING)
	hud.set_hp(0, 0.1)
	assert_eq(hud._bars[0].color, Hud.DANGER)
	hud.free()


func test_banners_stay_on_screen() -> void:
	for size in [Vector2(1920, 1080), Vector2(1080, 1920)]:
		var hud := _hud(size)
		for side in 2:
			hud.banner(side, "High Jump Kick", "Fighting")
			var label: Label = hud._banners[-1].label
			var rect := Rect2(label.global_position, label.size)
			assert_true(Rect2(Vector2.ZERO, size).encloses(rect), "banner %d off screen at %s: %s" % [side, size, rect])
		hud.free()
