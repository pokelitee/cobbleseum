extends TestCase
## The crowd (concepts_brief.md §12.7): figures fill the stands of a coliseum and nothing sits
## in the open; watchers of the arena's types watch from the front row; cheers rise and calm.


func test_figures_fill_most_seats_in_a_coliseum_and_none_in_the_open() -> void:
	var arena := Arena.create("stadium", 3)
	var crowd := Crowd.create(arena, 3)
	crowd.build()
	var count := crowd.figures.multimesh.instance_count
	assert_true(count > arena.seats.size() * 0.65 and count < arena.seats.size() * 0.85,
		"%d figures for %d seats" % [count, arena.seats.size()])
	var again := Crowd.create(arena, 3)
	again.build()
	assert_eq(again.figures.multimesh.instance_count, count, "the same battle seats the same crowd")
	crowd.free()
	again.free()
	arena.free()
	var open := Arena.create("grassland", 3)
	var empty := Crowd.create(open, 3)
	empty.build()
	assert_eq(empty.figures, null, "no crowd in the open")
	assert_true(empty.watcher_seats(4).is_empty())
	empty.free()
	open.free()


func test_watchers_suit_the_arena_and_spread_around_the_front_row() -> void:
	var roster := {
		"sprout": {"height": 0.8}, "vine": {"height": 1.2}, "tree": {"height": 6.0},
		"ember": {"height": 1.0}, "seed": {"height": 0.5},
	}
	var species := {
		"sprout": {"types": ["Grass"]}, "vine": {"types": ["Grass", "Poison"]}, "tree": {"types": ["Grass"]},
		"ember": {"types": ["Fire"]}, "seed": {"types": ["Bug"]},
	}
	var rng := RandomNumberGenerator.new()
	var chosen := Crowd.choose_watchers(["Grass", "Bug"], roster, species, ["vine"], rng, 4)
	chosen.sort()
	assert_eq(chosen, ["seed", "sprout"] as Array[String], "of the arena's types, fitting a seat, not a fighter")
	var arena := Arena.create("stadium", 3)
	var crowd := Crowd.create(arena, 3)
	var seats := crowd.watcher_seats(4)
	assert_eq(seats.size(), 4)
	for seat in seats:
		assert_almost_eq(seat.origin.y, Coliseum.row(0).y, 1e-4, "in the front row")
	for i in 4:
		for j in range(i + 1, 4):
			assert_true(seats[i].origin.distance_to(seats[j].origin) > 10.0, "spread around the stands")
	crowd.free()
	arena.free()


func test_cheers_hold_then_calm_and_freeze_in_hit_stop() -> void:
	var arena := Arena.create("stadium", 3)
	var crowd := Crowd.create(arena, 3)
	crowd.build()
	crowd.cheer(0.5)
	crowd.cheer(0.3)
	assert_eq(crowd.excitement, 0.5, "a smaller cheer doesn't quieten a bigger one")
	crowd.cheer(1.0, 10)
	for i in 10:
		crowd.next_frame()
	assert_eq(crowd.excitement, 1.0, "held through a knockout")
	crowd.set_time_scale(0.0)
	crowd.next_frame()
	assert_eq(crowd.excitement, 1.0, "frozen in hit-stop")
	crowd.set_time_scale(1.0)
	for i in 60:
		crowd.next_frame()
	assert_true(crowd.excitement < 0.2, "calms within a few seconds: %.2f" % crowd.excitement)
	crowd.free()
	arena.free()


func test_a_preset_sets_how_full_the_stands_are_and_how_many_watch() -> void:
	var arena := Arena.create("stadium", 3)
	var empty := Crowd.create(arena, 3, {"fill": 0.0, "watchers": 0})
	empty.build()
	assert_eq(empty.figures, null, "empty stands")
	assert_true(empty.watcher_seats(empty.watcher_count).is_empty(), "and no watchers")
	var full := Crowd.create(arena, 3, {"fill": 1.0, "watchers": 6})
	full.build()
	assert_eq(full.figures.multimesh.instance_count, arena.seats.size(), "every seat taken")
	assert_eq(full.watcher_seats(full.watcher_count).size(), 6)
	var default := Crowd.create(arena, 3)
	assert_eq([default.fill, default.watcher_count], [Crowd.FILL, Crowd.WATCHERS], "defaults where a preset says nothing")
	empty.free()
	full.free()
	default.free()
	arena.free()


func test_crowd_settings_are_checked() -> void:
	var base := {"field": "paved", "venue": "coliseum", "sky": [], "sun": {}, "ambient": {}, "fog": {}}
	assert_eq(Arenas._problem(base), "")
	for crowd: Variant in [{"fill": 1.5}, {"fill": "most"}, {"watchers": -1}, {"watchers": 2.5}, {"watchers": Arenas.MAX_WATCHERS + 1}, {"size": 3}, "full"]:
		var entry := base.duplicate()
		entry.crowd = crowd
		assert_false(Arenas._problem(entry).is_empty(), "rejects %s" % [crowd])
	var good := base.duplicate()
	good.crowd = {"fill": 0.5, "watchers": 2}
	assert_eq(Arenas._problem(good), "")
