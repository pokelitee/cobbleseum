extends "res://game/presentation/move_sequences/styles/rush.gd"
## Sucker Punch, in Cobblemon's own pieces; phases it has none for are the rush style's.


func speed() -> float:
	return 1.5


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("suckerpunch_target1", "target", {"nudge": 0.35})
	steps.on_foe("suckerpunch_target2", "target", {"delay": 0.13, "nudge": 0.35})
	steps.on_foe("suckerpunch_targethit", "target", {"delay": 0.15, "nudge": 0.35})
	steps.on_foe("suckerpunch_targetspark", "target", {"delay": 0.15, "nudge": 0.35})
