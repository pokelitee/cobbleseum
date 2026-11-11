extends TestCase
## Arenas (concepts_brief.md §12.7): which biome a battle gets, and that building one is
## repeatable and leaves the battle floor clear.


func test_a_requested_biome_wins() -> void:
	for name in ArenaBiomes.NAMES:
		assert_eq(ArenaBiomes.choose(name, ["Fire"], 3), name)


func test_otherwise_the_seed_picks_from_biomes_that_suit_the_types() -> void:
	var picked := {}
	for seed in 20:
		picked[ArenaBiomes.choose("", ["Fire", "Ice"], seed)] = true
	assert_eq(picked.keys().size(), 4, "grassland, stadium, volcano and snowfield: %s" % [picked.keys()])
	assert_true(picked.has("volcano") and picked.has("snowfield"))
	assert_eq(ArenaBiomes.choose("", ["Fire"], 5), ArenaBiomes.choose("", ["Fire"], 5), "same seed, same arena")
	assert_eq(ArenaBiomes.choose("nowhere", ["Normal"], 0), ArenaBiomes.choose("", ["Normal"], 0), "unknown names are ignored")


func test_every_biome_builds_the_same_way_twice_with_seats() -> void:
	for name in ArenaBiomes.NAMES:
		var first := Arena.create(name, 9)
		var second := Arena.create(name, 9)
		assert_eq(first._blocks.size(), second._blocks.size(), name)
		assert_eq(first._blocks[100], second._blocks[100], name)
		assert_true(first.seats.size() > 20, "%s has room for spectators" % name)
		for seat in first.seats:
			assert_true(Vector2(seat.origin.x, seat.origin.z).length() > Arena.FLOOR_RADIUS + Arena.RIM_WIDTH, name)
		first.free()
		second.free()


func test_nothing_stands_on_the_battle_floor() -> void:
	var arena := Arena.create("grassland", 4)
	for entry: Array in arena._blocks + arena._glowing:
		var at: Vector3 = (entry[0] as Transform3D).origin
		var top := at.y + (entry[0] as Transform3D).basis.get_scale().y * 0.5
		if Vector2(at.x, at.z).length() <= Arena.FLOOR_RADIUS:
			assert_true(top <= 0.001, "floor blocks end at the floor: %s" % at)
	arena.free()


func test_the_stadium_rises_around_the_field_with_seats_in_the_stands() -> void:
	var arena := Arena.create("stadium", 3, ["Garchomp", "Greninja"])
	assert_true(Stadium.top_height() > 12.0, "tall enough to read as a stadium: %.1f m" % Stadium.top_height())
	assert_true(Stadium.wall_radius() > Arena.FLOOR_RADIUS + 3.0, "an apron between the field and the wall")
	assert_true(arena.camera_limit < Stadium.wall_radius(), "cameras stay inside the wall")
	for seat in arena.seats:
		assert_true(seat.origin.y > Stadium.WALL_HEIGHT, "seats are in the stands")
	assert_true(arena.seats.size() > 500)
	var labels := arena.find_children("*", "Label3D", false, false)
	assert_eq(labels.size(), 1, "the scoreboard")
	assert_true((labels[0] as Label3D).text.contains("GARCHOMP"))
	arena.free()


func test_cameras_are_kept_inside_the_limit() -> void:
	assert_eq(CameraRig.keep_inside(Vector3(3, 2, 4), 10.0), Vector3(3, 2, 4))
	var pulled := CameraRig.keep_inside(Vector3(30, 2, 40), 10.0)
	assert_almost_eq(Vector2(pulled.x, pulled.z).length(), 10.0, 1e-4)
	assert_eq(pulled.y, 2.0, "height is kept")

