extends TestCase
## What a name plate's effect row shows (concepts_brief.md §12.5).


func _keys(entries: Array[Dictionary]) -> Array:
	return entries.map(func(entry: Dictionary) -> String: return entry.key)


func test_status_confusion_and_screens_in_badge_order() -> void:
	var fighter := Fighter.new()
	var effects := PlateEffects.new()
	assert_eq(effects.read(fighter), [] as Array[Dictionary], "nothing to show")
	fighter.arena.set_screen(0, "lightscreen", 10)
	fighter.arena.set_screen(1, "reflect", 10)
	fighter.confusion_ticks = 5
	fighter.status = "par"
	fighter.status_ticks = 5
	assert_eq(_keys(effects.read(fighter)), ["par", "confusion", "lightscreen"], "only its own side's screens")


func test_timers_drain_from_the_standard_length() -> void:
	var fighter := Fighter.new()
	var effects := PlateEffects.new()
	var full := PlateEffects.standard_ticks("brn")
	fighter.status = "brn"
	fighter.status_ticks = full / 2
	assert_almost_eq(effects.read(fighter)[0].left, 0.5, 1e-3, "a clip starting mid-burn shows it half gone")
	fighter.status_ticks = full / 4
	assert_almost_eq(effects.read(fighter)[0].left, 0.25, 1e-3)


func test_renewed_and_longer_effects_restart_full() -> void:
	var fighter := Fighter.new()
	var effects := PlateEffects.new()
	var screen := PlateEffects.standard_ticks("reflect")
	fighter.arena.set_screen(0, "reflect", screen / 2)
	effects.read(fighter)
	fighter.arena.set_screen(0, "reflect", screen * 2)
	assert_almost_eq(effects.read(fighter)[0].left, 1.0, 1e-6, "a longer screen (Light Clay) starts full")
	fighter.arena.set_screen(0, "reflect", screen)
	assert_almost_eq(effects.read(fighter)[0].left, 0.5, 1e-6)
	fighter.status = "slp"
	fighter.status_ticks = 40
	var sleep: Dictionary = effects.read(fighter).filter(func(e: Dictionary) -> bool: return e.key == "slp")[0]
	assert_almost_eq(sleep.left, 1.0, 1e-6, "sleep's rolled length is what it starts with")


func test_an_effect_that_ends_is_dropped_and_comes_back_full() -> void:
	var fighter := Fighter.new()
	var effects := PlateEffects.new()
	fighter.confusion_ticks = 10
	effects.read(fighter)
	fighter.confusion_ticks = 0
	assert_eq(effects.read(fighter), [] as Array[Dictionary])
	fighter.confusion_ticks = PlateEffects.standard_ticks("confusion")
	assert_almost_eq(effects.read(fighter)[0].left, 1.0, 1e-6)


func test_changed_stat_stages_follow_the_timed_effects() -> void:
	var fighter := Fighter.new()
	var effects := PlateEffects.new()
	fighter.boosts.spe = -1
	fighter.boosts.atk = 2
	fighter.status = "brn"
	fighter.status_ticks = 10
	var entries := effects.read(fighter)
	assert_eq(_keys(entries), ["brn", "atk", "spe"], "unchanged stats are left out")
	assert_eq(entries[1].stages, 2)
	assert_eq(entries[2].stages, -1)
	assert_false(entries[1].has("left"), "stages have no timer")
	fighter.boosts.atk = 0
	assert_eq(_keys(effects.read(fighter)), ["brn", "spe"], "gone once the stage wears off")
