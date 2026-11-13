extends TestCase
## Arenas (concepts_brief.md §12.7): the presets, which one a battle gets, and that building
## one is repeatable and leaves the battle floor clear.


func _arc_vertices(arena: Arena) -> Array:
	var counts := []
	for child in arena.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is ArrayMesh:
			counts.append((child.mesh as ArrayMesh).surface_get_array_len(0))
	return counts


func test_every_preset_file_is_valid() -> void:
	var files := Array(DirAccess.get_files_at(Arenas.PRESETS_DIR)).filter(func(f: String) -> bool: return f.ends_with(".json"))
	assert_eq(Arenas.names().size(), files.size(), "every preset loads: %s" % [Arenas.names()])
	for name in ["grassland", "beach", "volcano", "snowfield", "cave", "stadium"]:
		assert_true(Arenas.all().has(name), name)
	assert_eq(Arenas._problem({"field": "lava", "venue": "open"}).is_empty(), false, "unknown fields are caught")
	assert_eq(Arenas._problem({"field": "paved", "venue": "moon"}).is_empty(), false, "unknown venues are caught")


func test_a_requested_arena_wins() -> void:
	for name in Arenas.names():
		assert_eq(Arenas.choose(name, ["Fire"], 3), name)


func test_otherwise_the_seed_picks_from_arenas_that_suit_the_types() -> void:
	var picked := {}
	for seed in 40:
		picked[Arenas.choose("", ["Fire", "Ice"], seed)] = true
	# Grassland and stadium are always offered; volcano suits Fire, snowfield and the frost
	# coliseum suit Ice.
	assert_eq(picked.keys().size(), 5, "%s" % [picked.keys()])
	assert_true(picked.has("volcano") and picked.has("snowfield") and picked.has("frost_coliseum"))
	assert_eq(Arenas.choose("", ["Fire"], 5), Arenas.choose("", ["Fire"], 5), "same seed, same arena")
	assert_eq(Arenas.choose("nowhere", ["Normal"], 0), Arenas.choose("", ["Normal"], 0), "unknown names are ignored")


func test_a_coliseum_takes_any_field_and_theme() -> void:
	var terrain := Terrain.generate("grassland", SimRandom.new(4), true)
	assert_true(terrain.enclosed)
	for cell in terrain.world_cells(Terrain.WORLD_RADIUS):
		if cell.length() >= Rules.ARENA_RADIUS:
			assert_eq(terrain.ground_at(cell), 0.0, "flat from the wall out, under the apron: %s" % cell)
	assert_true(terrain.highest() > 0.0, "mounds and features inside")
	var arena := Arena.create("garden_coliseum", 4, [], terrain)
	assert_eq(arena.theme.stone, Color.html("#c9b48e"), "the preset's theme")
	assert_eq(arena.theme.slab, Coliseum.DEFAULT_THEME.slab, "defaults fill the rest")
	assert_true(arena.camera_limit < Coliseum.wall_radius())
	assert_true(arena.seats.size() > 500, "seats are in the stands")
	assert_false(arena._look.has("water"))
	assert_true(absf(arena.surface_at(Vector2(0.5, 0.5), -100.0) - terrain.ground_at(Vector2(0.5, 0.5))) < Terrain.STEP,
		"the field is the faceted ground")
	arena.free()


func test_every_arena_builds_the_same_way_twice_with_seats() -> void:
	for name in Arenas.names():
		var first := Arena.create(name, 9)
		var second := Arena.create(name, 9)
		assert_eq(first._blocks.size(), second._blocks.size(), name)
		if not first._blocks.is_empty():
			assert_eq(first._blocks[first._blocks.size() / 2], second._blocks[second._blocks.size() / 2], name)
		assert_eq(_arc_vertices(first), _arc_vertices(second), name)
		assert_true(first.seats.size() > 20, "%s has room for spectators" % name)
		for seat in first.seats:
			assert_true(Vector2(seat.origin.x, seat.origin.z).length() > Rules.ARENA_RADIUS + 1.0, name)
		first.free()
		second.free()


func test_the_visible_ground_follows_the_battle_ground() -> void:
	var terrain := Terrain.generate("grassland", SimRandom.new(4))
	var arena := Arena.create("grassland", 4, [], terrain)
	var checked := 0
	for cell in terrain.cells():
		if terrain.kind_at(cell) != Terrain.Kind.GROUND:
			continue
		var shown := arena.surface_at(cell, -100.0)
		# Corners average the cells within a step, so the slope stays within a step of the
		# battle's terraces (fighters are drawn on the slope; the battle uses the terraces).
		assert_true(absf(shown - terrain.ground_at(cell)) < Terrain.STEP,
			"within a step at %s: %.2f vs %.2f" % [cell, shown, terrain.ground_at(cell)])
		checked += 1
	assert_true(checked > 300)
	arena.free()


func test_detail_patches_are_mostly_one_kind_in_proportion_to_the_weights() -> void:
	var arena := Arena.create("grassland", 4)
	var kinds := {"grass": 6, "flower": 2, "pebble": 1}
	assert_eq(arena._pick_detail(kinds, 0.0), "flower", "names are taken in order")
	assert_eq(arena._pick_detail(kinds, 0.3), "grass")
	assert_eq(arena._pick_detail(kinds, 0.95), "pebble")
	var counts := {}
	var same := 0
	for i in 2000:
		var at := Vector2(i * 13.7, i * 5.3)
		var kind := arena._pick_detail(kinds, arena._patch_roll(at))
		counts[kind] = counts.get(kind, 0) + 1
		if kind == arena._pick_detail(kinds, arena._patch_roll(at + Vector2(0.4, 0.0))):
			same += 1
	assert_true(same > 1800, "spots a cluster apart share their patch's kind: %d" % same)
	assert_almost_eq(counts.grass / 2000.0, 6.0 / 9.0, 0.08, "grass patches")
	assert_almost_eq(counts.flower / 2000.0, 2.0 / 9.0, 0.08, "flower patches")
	arena.free()


func test_the_coliseum_rises_around_the_field_with_seats_in_the_stands() -> void:
	var arena := Arena.create("stadium", 3, ["Garchomp", "Greninja"])
	assert_true(Coliseum.top_height() > 12.0, "tall enough to read as a coliseum: %.1f m" % Coliseum.top_height())
	assert_true(Coliseum.wall_radius() > Arena.FLOOR_RADIUS + 3.0, "an apron between the field and the wall")
	assert_true(arena.camera_limit < Coliseum.wall_radius(), "cameras stay inside the wall")
	for seat in arena.seats:
		assert_true(seat.origin.y > Coliseum.WALL_HEIGHT, "seats are in the stands")
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


func test_features_reach_their_battle_height() -> void:
	var terrain := Terrain.generate("volcano", SimRandom.new(11))
	var arena := Arena.create("volcano", 11, [], terrain)
	var vertices := PackedVector3Array()
	for child in arena.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is ArrayMesh:
			vertices.append_array((child.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	var features := terrain.cells().filter(func(c: Vector2) -> bool: return terrain.kind_at(c) != Terrain.Kind.GROUND)
	assert_true(features.size() > 0, "volcanoes have basalt and rocks")
	for cell: Vector2 in features:
		var top := -100.0
		for v in vertices:
			if Vector2(v.x, v.z).distance_to(cell) < 0.75:
				top = maxf(top, v.y)
		assert_true(top >= terrain.height_at(cell) - 0.05, "%s reaches %.1f (got %.2f)" % [cell, terrain.height_at(cell), top])
	arena.free()



func _lights(arena: Arena, type: Variant) -> Array:
	return arena.get_children().filter(func(child: Node) -> bool: return is_instance_of(child, type))


func test_every_arena_is_lit_and_graded_alike() -> void:
	for name in Arenas.names():
		var arena := Arena.create(name, 2)
		var world: WorldEnvironment = _lights(arena, WorldEnvironment)[0]
		var environment := world.environment
		assert_eq(environment.tonemap_mode, Environment.TONE_MAPPER_FILMIC, name)
		assert_true(environment.glow_enabled and environment.glow_hdr_threshold > 1.0, "%s: only glowing things bloom" % name)
		assert_true(environment.ssao_enabled, name)
		var sun: DirectionalLight3D = _lights(arena, DirectionalLight3D)[0]
		assert_true(sun.shadow_enabled and sun.light_angular_distance > 0.0, "%s: soft sun shadows" % name)
		arena.free()


func test_glowing_blocks_draw_past_the_bloom_threshold() -> void:
	var arena := Arena.create("volcano", 3)
	var glow := arena._material(true, false) as StandardMaterial3D
	assert_true(glow.albedo_color.r > ArenaLighting.HDR_THRESHOLD, "glowing cracks bloom")
	arena.free()


func test_only_floodlit_presets_light_the_field_from_the_roof() -> void:
	var night := Arena.create("night_stadium", 5)
	var floodlights := _lights(night, SpotLight3D)
	assert_eq(floodlights.size(), Coliseum.FLOODLIGHT_ANGLES.size())
	assert_eq(floodlights.filter(func(l: SpotLight3D) -> bool: return l.shadow_enabled).size(), 1, "one casts shadows")
	for light: SpotLight3D in floodlights:
		assert_true(light.position.y > Coliseum.top_height(), "from the roof")
		var aim := -light.transform.basis.z
		assert_true(aim.dot(-light.position.normalized()) > 0.99, "aimed at the centre")
	var sun: DirectionalLight3D = _lights(night, DirectionalLight3D)[0]
	assert_true(sun.light_energy < 0.3, "a dim moon, not a sun")
	night.free()
	var day := Arena.create("stadium", 5)
	assert_eq(_lights(day, SpotLight3D).size(), 0, "day stadiums leave them off")
	assert_eq(day._look.exposure, 1.0, "exposure defaults to 1")
	day.free()
