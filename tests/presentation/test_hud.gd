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


func test_captions_slide_in_on_screen_then_go() -> void:
	for size in [Vector2(1920, 1080), Vector2(1080, 1920)]:
		var hud := _hud(size)
		hud.caption("COMEBACK!", 1)
		for i in Hud.CAPTION_IN_FRAMES:
			hud.next_frame()
		var band: Control = hud._caption.band
		assert_eq(band.position.x, 0.0, "in place")
		assert_true(Rect2(Vector2.ZERO, size).encloses(Rect2(band.position, band.size)), "on screen at %s" % size)
		hud.caption("FINAL BLOW", 0)
		assert_eq(hud.get_children().filter(func(n: Node) -> bool: return n == band and not n.is_queued_for_deletion()), [], "a new caption replaces the old")
		for i in Hud.CAPTION_FRAMES:
			hud.next_frame()
		assert_eq(hud._caption, {}, "gone after CAPTION_FRAMES")
		hud.free()


func test_the_replay_tag_shows_while_the_plates_fade_and_stay_out() -> void:
	for size in [Vector2(1920, 1080), Vector2(1080, 1920)]:
		var hud := _hud(size)
		hud.show_replay()
		assert_true(hud.replay_showing())
		var tag: Control = hud._replay_tag
		assert_true(tag.find_children("*", "Label", true, false).any(func(l: Label) -> bool: return l.text == "REPLAY"))
		assert_true(Rect2(Vector2.ZERO, size).encloses(Rect2(tag.position, tag.size)), "on screen at %s" % size)
		var dot_alphas := {}
		for i in Hud.REPLAY_BLINK_FRAMES * 2:
			hud.next_frame()
			dot_alphas[hud._replay_dot.modulate.a] = true
		assert_eq(dot_alphas.size(), 2, "the dot blinks")
		hud.hide_replay()
		assert_false(hud.replay_showing())
		hud.show_victory(0, "Left", 0.5, 60.0)
		hud.next_frame()
		for panel in hud._panels:
			assert_eq(panel.modulate.a, 0.0, "plates stay out into the victory")
		hud.free()


func test_the_intro_subtitle_sits_under_the_names() -> void:
	for size in [Vector2(1920, 1080), Vector2(1080, 1920)]:
		var hud := _hud(size)
		hud.set_intro_subtitle("Frost Coliseum · Overtime")
		var label: Label = hud._intro.get_child(-1)
		assert_eq(label.text, "Frost Coliseum · Overtime")
		assert_true(label.position.y >= hud._intro_box.position.y + hud._intro_box.size.y, "below the names")
		assert_true(label.position.y + label.size.y <= size.y, "on screen at %s" % size)
		hud.free()
