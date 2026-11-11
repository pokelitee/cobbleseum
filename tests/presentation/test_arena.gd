extends TestCase
## Arenas (concepts_brief.md §12.7): which biome a battle gets, and that building one is
## repeatable and leaves the battle floor clear.


func _arc_vertices(arena: Arena) -> Array:
	var counts := []
	for child in arena.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is ArrayMesh:
			counts.append((child.mesh as ArrayMesh).surface_get_array_len(0))
	return counts


func test_a_requested_biome_wins() -> void:
	for name in Terrain.BIOMES:
		assert_eq(Terrain.choose_biome(name, ["Fire"], 3), name)


func test_otherwise_the_seed_picks_from_biomes_that_suit_the_types() -> void:
	var picked := {}
	for seed in 20:
		picked[Terrain.choose_biome("", ["Fire", "Ice"], seed)] = true
	assert_eq(picked.keys().size(), 4, "grassland, stadium, volcano and snowfield: %s" % [picked.keys()])
	assert_true(picked.has("volcano") and picked.has("snowfield"))
	assert_eq(Terrain.choose_biome("", ["Fire"], 5), Terrain.choose_biome("", ["Fire"], 5), "same seed, same arena")
	assert_eq(Terrain.choose_biome("nowhere", ["Normal"], 0), Terrain.choose_biome("", ["Normal"], 0), "unknown names are ignored")


func test_every_biome_builds_the_same_way_twice_with_seats() -> void:
	for name in Terrain.BIOMES:
		var first := Arena.create(name, 9)
		var second := Arena.create(name, 9)
		assert_eq(first._blocks.size(), second._blocks.size(), name)
		assert_eq(first._blocks[first._blocks.size() / 2], second._blocks[second._blocks.size() / 2], name)
		assert_eq(_arc_vertices(first), _arc_vertices(second), name)
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
	assert_eq(labels.size(), 2, "a screen at each end")
	assert_true((labels[0] as Label3D).text.contains("GARCHOMP"))
	arena.free()


func test_cameras_are_kept_inside_the_limit() -> void:
	assert_eq(CameraRig.keep_inside(Vector3(3, 2, 4), 10.0), Vector3(3, 2, 4))
	var pulled := CameraRig.keep_inside(Vector3(30, 2, 40), 10.0)
	assert_almost_eq(Vector2(pulled.x, pulled.z).length(), 10.0, 1e-4)
	assert_eq(pulled.y, 2.0, "height is kept")


func test_ring_segments_meet_without_gaps() -> void:
	var arena := Arena.new()
	arena._biome = ArenaBiomes.BIOMES.stadium
	var rng := RandomNumberGenerator.new()
	arena.add_arc_ring(5.0, 6.0, 0.0, 1.0, Color.WHITE, rng, 0.0)
	var mesh: ArrayMesh = (arena._arcs[false] as SurfaceTool).commit()
	var top := 0
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var area := 0.0
	for i in range(0, vertices.size(), 3):
		var a := vertices[i]
		var b := vertices[i + 1]
		var c := vertices[i + 2]
		if is_equal_approx(a.y, 1.0) and is_equal_approx(b.y, 1.0) and is_equal_approx(c.y, 1.0):
			area += (b - a).cross(c - a).length() * 0.5
			top += 1
	assert_almost_eq(area, PI * (36.0 - 25.0), 0.05, "the top covers the ring exactly")
	arena.free()


func test_the_floor_follows_the_battle_terrain() -> void:
	var terrain := Terrain.generate("volcano", SimRandom.new(11))
	var arena := Arena.create("volcano", 11, [], terrain)
	var raised := terrain.cells().filter(func(c: Vector2) -> bool: return terrain.height_at(c) > 0.0)
	assert_true(raised.size() > 0, "volcanoes have plateaus and spires")
	var cell: Vector2 = raised[0]
	var tops := arena._blocks.filter(func(e: Array) -> bool:
		var at: Vector3 = (e[0] as Transform3D).origin
		return is_equal_approx(at.x, cell.x) and is_equal_approx(at.z, cell.y))
	var top := 0.0
	for entry: Array in tops:
		var t: Transform3D = entry[0]
		top = maxf(top, t.origin.y + t.basis.get_scale().y * 0.5)
	assert_almost_eq(top, terrain.height_at(cell), 1e-4, "the blocks reach the ground's height")
	arena.free()

