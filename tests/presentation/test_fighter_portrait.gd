extends TestCase
## How HUD portraits frame a fighter (concepts_brief.md §12.5).

const FRONT := Vector3(0, 0, 1)


## The corners of a box from `low` to `high`.
func _box(low: Vector3, high: Vector3) -> PackedVector3Array:
	var points := PackedVector3Array()
	for corner in 8:
		points.append(Vector3(high.x if corner & 1 else low.x, high.y if corner & 2 else low.y, high.z if corner & 4 else low.z))
	return points


func _top(shot: Dictionary) -> float:
	return (shot.transform as Transform3D).origin.y + shot.size * 0.5


func test_tall_bodies_get_a_bust_from_the_top() -> void:
	var shot := FighterPortrait.frame(_box(Vector3(-0.5, 0, -0.5), Vector3(0.5, 4, 0.5)), null, FRONT)
	var side := 4.0 * FighterPortrait.BUST_SHARE
	assert_almost_eq(shot.size, side * (1.0 + 2.0 * FighterPortrait.MARGIN), 1e-4)
	assert_almost_eq(_top(shot), 4.0 + side * FighterPortrait.MARGIN, 1e-4, "the top of the head, with a margin")
	assert_almost_eq((shot.transform as Transform3D).origin.x, 0.0, 1e-4)
	assert_true((shot.transform as Transform3D).origin.z > 0.5, "in front of the body")


func test_small_bodies_are_framed_whole() -> void:
	var shot := FighterPortrait.frame(_box(Vector3(-0.3, 0, -0.3), Vector3(0.3, 0.8, 0.3)), null, FRONT)
	assert_almost_eq(shot.size, 0.8 * (1.0 + 2.0 * FighterPortrait.MARGIN), 1e-4)
	assert_true(_top(shot) - shot.size <= 0.0, "feet in frame")


func test_long_bodies_centre_on_the_head_within_the_silhouette() -> void:
	var points := _box(Vector3(-3, 0, -0.5), Vector3(3, 1.5, 0.5))
	var shot := FighterPortrait.frame(points, Vector3(2, 1, 0), FRONT)
	assert_almost_eq(shot.size, 1.5 * (1.0 + 2.0 * FighterPortrait.MARGIN), 1e-4, "as tall as the body")
	assert_almost_eq((shot.transform as Transform3D).origin.x, 2.0, 1e-4, "on the head")
	shot = FighterPortrait.frame(points, Vector3(3, 1, 0), FRONT)
	assert_almost_eq((shot.transform as Transform3D).origin.x, 3.0 - 0.75, 1e-4, "kept within the body")


func test_a_missing_model_gives_no_portrait() -> void:
	assert_eq(FighterPortrait.create("res://cache/build/missing.scn", 1.0, 1.0), null)
