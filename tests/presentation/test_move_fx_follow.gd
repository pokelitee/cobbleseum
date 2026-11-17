extends TestCase
## Move-effect pieces placed on a fighter's body follow it; pieces on the ground stay
## (concepts_brief.md §12.5).


func test_an_aura_follows_its_fighter() -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var view := FighterView.new()
	view.height = 1.0
	root.add_child(view)
	var fx := MoveFX.new()
	root.add_child(fx)
	fx.guard(view)
	var shell: Node3D = fx._effects[0].node
	var before := shell.position
	view.position += Vector3(3, 0, 1)
	fx.next_frame()
	assert_true(shell.position.is_equal_approx(before + Vector3(3, 0, 1)), "%s -> %s" % [before, shell.position])
	fx.free()
	view.free()


func test_ground_pieces_stay_in_the_world() -> void:
	var ground := RegEx.create_from_string(CobblemonMoveFX.GROUND_PIECES)
	for piece in ["bodyslam_impactfloor", "bulldoze_actorquake", "explosion_actorbigring", "spore_land", "quickattack_dust"]:
		assert_true(ground.search(piece) != null, piece)
	for piece in ["swordsdance_actor", "statup_actor", "heal_sparkles", "shadowball_actorflaring", "stringshot_target1", "impact_fire"]:
		assert_true(ground.search(piece) == null, piece)
