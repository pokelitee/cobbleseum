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


func test_plates_show_types_and_the_hp_percentage() -> void:
	var hud := Hud.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	hud.setup(["Left", "Right"], Vector2(1920, 1080), [["Fire", "Flying"], ["Water"]])
	var pills := hud._badge_rows[0].get_children().map(func(l: Label) -> String: return l.text)
	assert_eq(pills, ["FIRE", "FLYING"])
	hud.set_status(0, "brn", true)
	assert_eq(hud._badge_rows[0].get_child_count(), 3, "status badges follow the type pills")
	hud.set_hp(1, 0.423)
	assert_eq(hud._percents[1].text, "43%", "rounded up, so a fighter with HP left never shows 0%")
	hud.set_hp(1, 0.0)
	assert_eq(hud._percents[1].text, "0%")
	hud.free()


func test_plain_text_uses_the_body_font() -> void:
	UiFonts.use_by_default()
	var label := Label.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(label)
	assert_eq(label.get_theme_font("font"), UiFonts.BODY)
	label.free()


func test_the_victory_card_slides_in_as_the_plates_fade() -> void:
	for size in [Vector2(1920, 1080), Vector2(1080, 1920)]:
		var hud := _hud(size)
		hud.show_victory(1, "Right", 0.623, 83.4)
		var texts := hud._victory.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
		assert_eq(texts, ["WINNER", "Right", "63% HP left  ·  1:23"])
		for i in Hud.VICTORY_IN_FRAMES:
			hud.next_frame()
		assert_eq(hud._victory.position.x, 0.0, "in place")
		assert_true(Rect2(Vector2.ZERO, size).encloses(Rect2(hud._victory.position, hud._victory.size)), "on screen at %s" % size)
		for panel in hud._panels:
			assert_eq(panel.modulate.a, 0.0, "plates faded out")
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
