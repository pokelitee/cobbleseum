extends TestCase
## Battlefield marks (BattleMarks, MarkTextures, concepts_brief.md §12.5): which mark a hit
## leaves, the pixel art they're drawn with, the cap with its fade, debris that settles, and
## that every mark repeats from its key.


## Marks on a paved stadium, whose flat floor is 0 high everywhere.
func _marks() -> BattleMarks:
	var arena := Arena.create("stadium", 1)
	var marks := BattleMarks.new()
	marks.add_child(arena)
	marks.setup(7, arena)
	return marks


func _hit(kind := "scorch", radius := 0.8, debris := false) -> Dictionary:
	return {"kind": kind, "radius": radius, "debris": debris, "along": false}


func test_hits_mark_by_type_and_style() -> void:
	assert_eq(BattleMarks.describe("orb", "Fire", false, false, 0.1, false).kind, "scorch")
	assert_eq(BattleMarks.describe("bolt", "Electric", false, false, 0.1, false).kind, "scorch")
	assert_eq(BattleMarks.describe("beam", "Ice", false, false, 0.1, false).kind, "frost")
	assert_eq(BattleMarks.describe("stream", "Water", false, false, 0.1, false).kind, "splash")
	assert_eq(BattleMarks.describe("bullet", "Rock", false, false, 0.1, false).kind, "cracks")
	var punch := BattleMarks.describe("punch", "Fighting", true, false, 0.1, false)
	assert_eq(punch.kind, "scuff", "earthy blows skid")
	assert_true(punch.along, "scuffs turn along the blow")
	assert_eq(BattleMarks.describe("punch", "Fire", true, false, 0.1, false).kind, "scorch", "a fire punch still burns")
	for style in ["orb", "punch", "beam"]:
		assert_false(BattleMarks.describe(style, "Fire", style == "punch", false, 0.3, true).debris, "hits throw no debris: %s" % style)


func test_area_and_ground_moves_crack_or_crater_and_throw_debris() -> void:
	var quake := BattleMarks.describe("quake", "Ground", false, true, 0.0, false)
	assert_eq(quake.kind, "cracks")
	assert_true(quake.debris)
	assert_almost_eq(quake.radius, Rules.AREA_RADIUS * BattleMarks.AREA_SHARE, 0.001, "covers most of the area's reach")
	assert_eq(BattleMarks.describe("explosion", "Normal", false, true, 0.0, false).kind, "crater")
	assert_eq(BattleMarks.describe("orb", "Fire", false, true, 0.0, false).kind, "crater", "a fiery blast craters")
	var skyfall := BattleMarks.describe("skyfall", "Rock", false, false, 0.2, false)
	assert_eq(skyfall.kind, "crater")
	assert_true(skyfall.debris)
	assert_true(BattleMarks.describe("erupt", "Fire", false, false, 0.2, false).debris, "eruptions break the ground")


func test_heavier_hits_leave_bigger_marks() -> void:
	var light: float = BattleMarks.describe("orb", "Fire", false, false, 0.02, false).radius
	var heavy: float = BattleMarks.describe("orb", "Fire", false, false, 0.5, false).radius
	var big: float = BattleMarks.describe("orb", "Fire", false, false, 0.5, true).radius
	assert_true(light < heavy and heavy < big, "%f < %f < %f" % [light, heavy, big])
	assert_almost_eq(heavy, BattleMarks.HIT_RADIUS.y, 0.001, "capped at a heavy hit")


func test_textures_are_pixel_art_and_repeat() -> void:
	var ground := Color(0.42, 0.6, 0.3)
	for kind in MarkTextures.KINDS:
		for type in ["Fire", "Electric", "Psychic", "Water", "Ground"]:
			var drawn := MarkTextures.draw(kind, type, 1, ground)
			var image: Image = drawn.albedo
			assert_eq(image.get_width(), MarkTextures.size_of(kind))
			assert_eq(image.get_data(), MarkTextures.draw(kind, type, 1, ground).albedo.get_data(), "same pixels every time: %s %s" % [kind, type])
			var colours := {}
			var filled := 0
			for y in image.get_height():
				for x in image.get_width():
					var pixel := image.get_pixel(x, y)
					assert_true(pixel.a == 0.0 or pixel.a == 1.0, "opaque or clear: %s %s" % [kind, type])
					if pixel.a > 0.0:
						filled += 1
						colours[pixel.to_html()] = true
			assert_true(filled > 20, "%s %s draws something" % [kind, type])
			assert_true(colours.size() <= 6, "%s %s keeps to a few flat colours: %d" % [kind, type, colours.size()])
	assert_true(MarkTextures.draw("scorch", "Fire", 0, ground).emission != null, "embers glow")
	assert_true(MarkTextures.draw("scorch", "Electric", 0, ground).emission != null, "sparks glow")
	assert_eq(MarkTextures.draw("frost", "Ice", 0, ground).emission, null, "frost doesn't glow")
	assert_false(MarkTextures.draw("splash", "Water", 0, ground).albedo.get_data()
		== MarkTextures.draw("splash", "Water", 1, ground).albedo.get_data(), "variants differ")


func test_marks_paint_the_canvas_the_arena_draws() -> void:
	var marks := _marks()
	var arena: Arena = marks.get_child(0)
	assert_eq(marks.colour_at(Vector2(2, -1)).a, 0.0, "clear before")
	marks.add(_hit("splash", 0.8), "Water", Vector2(2, -1), 0.0, Vector2.ZERO, 3)
	assert_eq(marks.colour_at(Vector2(2, -1)).a, 1.0, "the stain's middle")
	assert_eq(marks.colour_at(Vector2(2, -2.2)).a, 0.0, "nothing past its edge")
	var surface: ShaderMaterial = arena._surfaces[0]
	assert_eq(surface.get_shader_parameter("MARKS"), marks.albedo_texture)
	assert_eq(surface.get_shader_parameter("MARKS_ORIGIN"), marks.origin)
	assert_eq(fmod(marks.origin.x * MarkTextures.PIXELS_PER_METRE, 1.0), 0.0, "on the ground's pixel grid")
	marks.free()


func test_fresh_burns_glow_then_cool() -> void:
	var marks := _marks()
	marks.add(_hit("scorch", 1.2), "Electric", Vector2.ZERO, 0.0, Vector2.ZERO, 3)
	var glowing := 0
	var canvas: Image = marks._glow_canvas
	for y in canvas.get_height():
		for x in canvas.get_width():
			var pixel := canvas.get_pixel(x, y)
			if pixel.a > 0.0:
				glowing += 1
				assert_almost_eq(pixel.a * 255.0 - 1.0, marks.frame_code(), 0.01, "stamped with the frame it was made on")
	assert_true(glowing > 0, "sparks glow")
	var middle: Vector2i = marks._marks[0].rect.get_center()
	assert_true(marks.glow_at(Vector2.ZERO) == canvas.get_pixel(middle.x, middle.y), "read by the floor's point")
	for i in BattleMarks.GLOW_FRAMES:
		marks.next_frame()
	assert_eq(marks._glow_canvas.get_used_rect().size, Vector2i.ZERO, "and are cleared once cool")
	assert_eq(marks.colour_at(Vector2.ZERO).a, 1.0, "the burn stays")
	marks.add(_hit("scorch", 1.2), "Fire", Vector2(5, 0), 0.0, Vector2.ZERO, 4, true)
	assert_eq(marks._glow_canvas.get_used_rect().size, Vector2i.ZERO, "settled marks have cooled")
	marks.free()


func test_scuffs_turn_along_the_blow() -> void:
	var across := []
	for along in [Vector2(1, 0), Vector2(0, 1)]:
		var marks := _marks()
		marks.add({"kind": "scuff", "radius": 1.0, "debris": false, "along": true}, "Normal", Vector2.ZERO, 0.0, along, 1)
		var rect: Rect2i = marks._canvas.get_used_rect()
		across.append(rect.size)
		marks.free()
	assert_true(across[0].x > across[0].y * 2, "streaks run along x: %s" % across[0])
	assert_true(across[1].y > across[1].x * 2, "and along z: %s" % across[1])


func test_the_same_key_gives_the_same_mark() -> void:
	var drawn := []
	for run in 2:
		var marks := _marks()
		marks.add(_hit("crater", 2.0, true), "Rock", Vector2(1, 1), 0.0, Vector2.ZERO, 42)
		for i in 60:
			marks.next_frame()
		var chunks := []
		for index in marks.debris_count():
			chunks.append(marks._debris.multimesh.get_instance_transform(index))
		drawn.append([marks._canvas.get_data(), chunks])
		marks.free()
	assert_eq(drawn[0], drawn[1])


func test_settled_marks_end_as_played_ones_do() -> void:
	var played := _marks()
	var settled := _marks()
	played.add(_hit("cracks", 2.0, true), "Ground", Vector2(-3, 2), 0.0, Vector2.ZERO, 9)
	settled.add(_hit("cracks", 2.0, true), "Ground", Vector2(-3, 2), 0.0, Vector2.ZERO, 9, true)
	assert_true(played.debris_count() >= BattleMarks.DEBRIS_PER_MARK.x)
	assert_eq(played.debris_count(), settled.debris_count())
	for i in BattleMarks.MAX_FLIGHT:
		played.next_frame()
	for index in played.debris_count():
		assert_false(played._chunks[index].flying, "landed")
		assert_false(settled._chunks[index].flying, "settled from the start")
		var a: Vector3 = played._chunks[index].position
		var b: Vector3 = settled._chunks[index].position
		assert_true(a.is_equal_approx(b), "same resting place: %s %s" % [a, b])
		assert_true(a.y > 0.0 and a.y < 0.1, "lying on the ground: %s" % a)
	played.free()
	settled.free()


func test_the_oldest_marks_dissolve_past_the_cap() -> void:
	var marks := _marks()
	for i in BattleMarks.CAP + 3:
		marks.add(_hit("splash", 0.5), "Water", Vector2(i % 7, i / 7) * 1.5 - Vector2(4, 4), 0.0, Vector2.ZERO, i)
	assert_eq(marks.count(), BattleMarks.CAP + 3, "fading marks stay while they fade")
	var oldest: Rect2i = marks._marks[0].rect
	var filled := func() -> int:
		var count := 0
		for y in range(oldest.position.y, oldest.end.y):
			for x in range(oldest.position.x, oldest.end.x):
				if marks._canvas.get_pixel(x, y).a > 0.0:
					count += 1
		return count
	var seen := {filled.call(): true}
	for i in BattleMarks.FADE_FRAMES:
		marks.next_frame()
		seen[filled.call()] = true
	assert_eq(marks.count(), BattleMarks.CAP)
	assert_eq(filled.call(), 0, "gone")
	assert_true(seen.size() <= BattleMarks.FADE_STEPS + 1, "dissolves in steps: %s" % [seen.keys()])
	assert_eq(int(marks._marks[0].fade), -1, "the rest stay")
	marks.free()


func test_debris_is_pooled() -> void:
	var marks := _marks()
	for i in 20:
		marks.add(_hit("crater", 2.0, true), "Rock", Vector2(i % 5, i / 5) * 3.0, 0.0, Vector2.ZERO, i, true)
	assert_eq(marks.debris_count(), BattleMarks.DEBRIS_POOL, "never more chunks than the pool")
	assert_eq(marks._debris.multimesh.instance_count, BattleMarks.DEBRIS_POOL, "one draw for all of it")
	marks.free()


func test_marks_shade_from_the_arenas_ground() -> void:
	var stadium := Arena.create("stadium", 1)
	assert_eq(stadium.ground_colour(), stadium.theme.slab, "paving shades a stadium's marks")
	stadium.free()
	var volcano := Arena.create("volcano", 1)
	assert_eq(volcano.ground_colour(), ArenaFields.FIELDS.volcano.colours[0])
	volcano.free()
