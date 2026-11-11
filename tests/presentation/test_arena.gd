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
