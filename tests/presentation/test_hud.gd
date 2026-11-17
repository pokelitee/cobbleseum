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
	var pills := hud._type_rows[0].get_children().map(func(l: Label) -> String: return l.text)
	assert_eq(pills, ["FIRE", "FLYING"])
	hud.set_effects(0, [{"key": "brn", "left": 1.0}] as Array[Dictionary])
	assert_eq(hud._type_rows[0].get_child_count(), 2, "status badges stay out of the type row")
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


func test_each_plate_holds_a_portrait_or_the_initial_beside_the_bar() -> void:
	var picture := ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGBA8))
	for size in [Vector2(1920, 1080), Vector2(1080, 1920)]:
		var hud := Hud.new()
		(Engine.get_main_loop() as SceneTree).root.add_child(hud)
		hud.setup(["Left", "Right"], size, [[], []], [picture, null])
		for side in 2:
			var panel: Control = hud._panels[side]
			var slot: Control = panel.get_child(1)
			var slot_rect := Rect2(slot.global_position, slot.size)
			var track: Control = hud._bars[side].get_parent()
			var track_rect := Rect2(track.global_position, track.size)
			assert_false(slot_rect.intersects(track_rect), "slot %d clear of the bar at %s" % [side, size])
			assert_true(Rect2(Vector2.ZERO, size).encloses(slot_rect), "slot %d on screen at %s" % [side, size])
			var plate: Control = panel.get_child(0)
			assert_true(Rect2(plate.global_position, plate.size).encloses(slot_rect), "slot %d on its plate at %s" % [side, size])
		var shown: TextureRect = hud._panels[0].get_child(1).get_child(0)
		assert_eq(shown.texture, picture)
		assert_false(shown.flip_h, "side A faces the middle as rendered")
		var initial: Label = hud._panels[1].get_child(1).get_child(0)
		assert_eq(initial.text, "R", "no portrait: the initial")
		hud.free()
	var hud := Hud.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	hud.setup(["Left", "Right"], Vector2(1920, 1080), [[], []], [picture, picture])
	assert_true((hud._panels[1].get_child(1).get_child(0) as TextureRect).flip_h, "the right-hand plate's portrait faces the middle")
	hud.free()


func test_a_shiny_has_a_sparkle_on_its_plate_in_both_formats() -> void:
	for size in [Vector2(1920, 1080), Vector2(1080, 1920)]:
		var hud := Hud.new()
		(Engine.get_main_loop() as SceneTree).root.add_child(hud)
		hud.setup(["Left", "Right"], size, [["Fire"], ["Water"]], [null, null], [false, true])
		var marks := hud._panels.map(func(p: Control) -> Array: return p.get_children().filter(func(c: Node) -> bool: return c is Hud.ShinyMark))
		assert_eq(marks.map(func(m: Array) -> int: return m.size()), [0, 1], "only the shiny side at %s" % size)
		var mark: Control = marks[1][0]
		var row: Control = hud._type_rows[1]
		assert_true(mark.position.x + mark.size.x <= row.position.x, "the type pills make room for it at %s" % size)
		var name_label: Label = hud._panels[1].get_children().filter(func(c: Node) -> bool: return c is Label)[0]
		assert_true(mark.position.x >= name_label.position.x + name_label.get_minimum_size().x, "after the name at %s" % size)
		hud.free()


## Every effect at once, as PlateEffects would give them.
func _all_effects() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for key: String in PlateEffects.TIMED:
		entries.append({"key": key, "left": 0.5})
	for stat: String in PlateEffects.STAGES:
		entries.append({"key": stat, "stages": 6 if stat.begins_with("s") else -6})
	return entries


func test_effects_sit_in_a_row_under_the_bar_on_screen() -> void:
	for size in [Vector2(1920, 1080), Vector2(1080, 1920)]:
		var hud := _hud(size)
		for side in 2:
			hud.banner(side, "High Jump Kick", "Fighting")
			hud.set_effects(side, _all_effects())
			var row: Control = hud._effect_rows[side]
			var rect := Rect2(row.global_position, row.size * row.scale)
			var track: Control = hud._bars[side].get_parent()
			var track_rect := Rect2(track.global_position, track.size)
			assert_true(rect.position.y >= track_rect.end.y, "row %d under the bar at %s" % [side, size])
			assert_true(rect.position.x >= track_rect.position.x - 0.5 and rect.end.x <= track_rect.end.x + 0.5,
				"row %d shrinks to the bar's width at %s: %s" % [side, size, rect])
			assert_true(Rect2(Vector2.ZERO, size).encloses(rect), "row %d on screen at %s" % [side, size])
			var banner: Label = hud._banners[-1].label
			assert_false(rect.intersects(Rect2(banner.global_position, banner.size)), "row %d clear of its banner at %s" % [side, size])
			var credit: Label = hud.get_children().filter(func(n: Node) -> bool: return n is Label and n.text == Hud.cobblemon_credit(false))[0]
			assert_false(rect.intersects(Rect2(credit.position, credit.get_minimum_size())), "row %d clear of the credit line at %s" % [side, size])
		hud.free()


func test_effect_badges_come_and_go_in_order_with_their_timers() -> void:
	var hud := _hud()
	hud.set_effects(0, [{"key": "par", "left": 0.75}, {"key": "reflect", "left": 0.5}] as Array[Dictionary])
	var row: HBoxContainer = hud._effect_rows[0]
	assert_eq(row.get_child_count(), 2)
	var codes := row.get_children().map(func(b: HudBadge) -> String: return (b.find_children("*", "Label", false, false)[0] as Label).text)
	assert_eq(codes, ["PAR", "REFL"])
	assert_almost_eq((row.get_child(0) as HudBadge).left(), 0.75, 1e-3, "the timer drains")
	hud.set_effects(0, [{"key": "confusion", "left": 1.0}, {"key": "reflect", "left": 0.25}] as Array[Dictionary])
	assert_eq(row.get_child_count(), 2, "paralysis went")
	assert_eq((row.get_child(0) as HudBadge), hud._effects[0].confusion, "in the order given")
	assert_almost_eq((row.get_child(1) as HudBadge).left(), 0.25, 1e-3)
	hud.set_effects(0, [] as Array[Dictionary])
	assert_eq(row.get_child_count(), 0)
	hud.free()


func test_the_right_hand_landscape_row_lines_up_with_its_portrait_end() -> void:
	var hud := _hud()
	hud.set_effects(1, [{"key": "brn", "left": 1.0}] as Array[Dictionary])
	var row: Control = hud._effect_rows[1]
	var track: Control = hud._bars[1].get_parent()
	assert_almost_eq(row.global_position.x + row.size.x, track.global_position.x + track.size.x, 0.5)
	hud.free()


func test_every_badge_has_an_icon_and_a_code() -> void:
	for key: String in PlateEffects.TIMED:
		assert_true(Hud.STATUS_BADGES.has(key), "%s has a code" % key)
		var rows: Array = HudBadge.ICONS[key]
		for row: String in rows:
			assert_eq(row.length(), (rows[0] as String).length(), "%s's rows are even" % key)


func test_stat_stages_show_their_arrow_and_count_and_redraw_when_it_changes() -> void:
	var hud := _hud()
	hud.set_effects(0, [{"key": "atk", "stages": 2}, {"key": "spe", "stages": -1}] as Array[Dictionary])
	var row: HBoxContainer = hud._effect_rows[0]
	var texts := row.get_children().map(func(b: HudBadge) -> Array:
		return b.find_children("*", "Label", false, false).map(func(l: Label) -> String: return l.text))
	assert_eq(texts, [["ATK", "2"], ["SPE", "1"]])
	assert_eq((row.get_child(0) as HudBadge).left(), -1.0, "no timer")
	var first: HudBadge = row.get_child(0)
	hud.set_effects(0, [{"key": "atk", "stages": 2}, {"key": "spe", "stages": -1}] as Array[Dictionary])
	assert_eq(row.get_child(0), first, "kept while its count holds")
	hud.set_effects(0, [{"key": "atk", "stages": 1}] as Array[Dictionary])
	assert_eq(row.get_child_count(), 1)
	assert_eq((row.get_child(0).find_children("*", "Label", false, false)[1] as Label).text, "1", "redrawn with its new count")
	hud.free()
