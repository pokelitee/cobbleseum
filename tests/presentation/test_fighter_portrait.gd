extends TestCase
## How HUD portraits frame a fighter (concepts_brief.md §12.5).

const FRONT := Vector3(0, 0, 1)


## The corners of a box from `low` to `high`, each `copies` times.
func _box(low: Vector3, high: Vector3, copies := 1) -> PackedVector3Array:
	var points := PackedVector3Array()
	for copy in copies:
		for corner in 8:
			points.append(Vector3(high.x if corner & 1 else low.x, high.y if corner & 2 else low.y, high.z if corner & 4 else low.z))
	return points


func _top(shot: Dictionary) -> float:
	return (shot.transform as Transform3D).origin.y + shot.size * 0.5


func _x(shot: Dictionary) -> float:
	return (shot.transform as Transform3D).origin.x


func _framed(side: float) -> float:
	return side * (1.0 + 2.0 * FighterPortrait.MARGIN)


func test_tall_bodies_get_a_head_and_shoulders_bust() -> void:
	var body := _box(Vector3(-0.5, 0, -0.5), Vector3(0.5, 4, 0.5))
	var shot := FighterPortrait.frame(body, _box(Vector3(-0.25, 3.5, -0.25), Vector3(0.25, 4, 0.25)), FRONT)
	var side := 0.5 * FighterPortrait.HEAD_SHARE
	assert_almost_eq(shot.size, _framed(side), 1e-4, "sized by the head")
	assert_almost_eq(_top(shot), 4.0 + side * FighterPortrait.MARGIN, 1e-4, "the top of the head, with a margin")
	assert_almost_eq(_x(shot), 0.0, 1e-4)
	assert_true((shot.transform as Transform3D).origin.z > 0.5, "in front of the body")


func test_wide_heads_keep_their_width() -> void:
	var body := _box(Vector3(-2, 0, -0.5), Vector3(2, 4, 0.5))
	var shot := FighterPortrait.frame(body, _box(Vector3(-1, 3.6, -0.25), Vector3(1, 4, 0.25)), FRONT)
	assert_almost_eq(shot.size, _framed(2.0 * FighterPortrait.HEAD_WIDTH_SHARE), 1e-4)


func test_thin_crests_and_whiskers_do_not_size_the_head() -> void:
	var body := _box(Vector3(-0.5, 0, -0.5), Vector3(0.5, 4, 0.5))
	var skull := _box(Vector3(-0.25, 3.0, -0.25), Vector3(0.25, 3.5, 0.25), 6)
	var head := skull + PackedVector3Array([Vector3(0, 4, 0), Vector3(0, 2.2, 0)])
	var shot := FighterPortrait.frame(body, head, FRONT)
	var side := 0.5 * FighterPortrait.HEAD_SHARE
	assert_almost_eq(shot.size, _framed(side), 1e-4, "the skull's size")
	var top := 3.5 + 0.5 * FighterPortrait.HEAD_TOP_ROOM
	assert_almost_eq(_top(shot), top + side * FighterPortrait.MARGIN, 1e-4, "a little room over the skull, not up to the crest")


func test_round_bodies_whose_head_is_most_of_them_are_framed_whole() -> void:
	var body := _box(Vector3(-0.4, 0, -0.4), Vector3(0.4, 0.8, 0.4))
	var shot := FighterPortrait.frame(body, _box(Vector3(-0.4, 0.2, -0.4), Vector3(0.4, 0.8, 0.4)), FRONT)
	assert_almost_eq(shot.size, _framed(0.8), 1e-4)
	assert_true(_top(shot) - shot.size <= 0.0, "feet in frame")


func test_bodies_without_a_head_bone_are_framed_whole() -> void:
	var shot := FighterPortrait.frame(_box(Vector3(-1, 0, -1), Vector3(1, 1.5, 1)), PackedVector3Array(), FRONT)
	assert_almost_eq(shot.size, _framed(2.0), 1e-4)
	assert_almost_eq(_x(shot), 0.0, 1e-4)


func test_the_square_stays_within_the_silhouette() -> void:
	var long := _box(Vector3(-3, 0, -0.5), Vector3(3, 2, 0.5))
	var shot := FighterPortrait.frame(long, _box(Vector3(2.6, 1.5, -0.2), Vector3(3, 2, 0.2)), FRONT)
	var side := 0.5 * FighterPortrait.HEAD_SHARE
	assert_almost_eq(_x(shot), 3.0 - side * 0.5, 1e-4, "kept within the body's end")
	var grazing := FighterPortrait.frame(long, _box(Vector3(2.6, 0.1, -0.2), Vector3(3, 0.6, 0.2)), FRONT)
	assert_almost_eq(_top(grazing) - grazing.size, -side * FighterPortrait.MARGIN, 1e-4, "a low head keeps the square off empty ground")


func test_a_missing_model_gives_no_portrait() -> void:
	assert_eq(FighterPortrait.create("res://cache/build/missing.scn", 1.0, 1.0), null)
