extends TestCase


func _sound() -> BattleSound:
	var root := TestFiles.fresh_dir("battle_sound")
	for file in ["pokemon/blastoise/blastoise_cry.ogg",
			"move/hydropump/hydropump_actor.ogg", "move/hydropump/hydropump_target.ogg",
			"move/closecombat/closecombat_actor_2.ogg", "move/closecombat/closecombat_actor_10.ogg",
			"move/closecombat/closecombat_actor_1.ogg",
			"move/impact_generic/impact_generic_fire_1.ogg", "move/impact_generic/impact_generic_fire_2.ogg"]:
		TestFiles.write_text(root.path_join(file), "")
	var sound := BattleSound.new()
	sound.setup(["blastoise", "cinderace"], root)
	return sound


func test_move_sounds_use_the_move_folder() -> void:
	var sound := _sound()
	assert_eq(sound.move_path("hydropump", "actor").get_file(), "hydropump_actor.ogg")
	assert_eq(sound.move_path("hydropump", "target").get_file(), "hydropump_target.ogg")
	assert_eq(sound.move_path("pyroball", "target"), "", "no folder means no sound")
	sound.free()


func test_variants_cycle_in_natural_order() -> void:
	var sound := _sound()
	var picks: Array[String] = []
	for i in 4:
		picks.append(sound.move_path("closecombat", "actor").get_file())
	assert_eq(picks, ["closecombat_actor_1.ogg", "closecombat_actor_2.ogg", "closecombat_actor_10.ogg",
		"closecombat_actor_1.ogg"] as Array[String])
	sound.free()


func test_impacts_follow_the_move_type() -> void:
	var sound := _sound()
	assert_eq(sound.impact_path("Fire").get_file(), "impact_generic_fire_1.ogg")
	assert_eq(sound.impact_path("Fire").get_file(), "impact_generic_fire_2.ogg")
	assert_eq(sound.impact_path("Fairy"), "")
	sound.free()


func test_cries_need_the_species_file() -> void:
	var sound := _sound()
	assert_eq(sound.cry_path(0).get_file(), "blastoise_cry.ogg")
	assert_eq(sound.cry_path(1), "", "cinderace has no cry in the fixture")
	sound.free()
