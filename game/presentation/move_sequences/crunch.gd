extends "res://game/presentation/move_sequences/styles/bite.gd"
## Crunch, in Cobblemon's own pieces; phases it has none for are the bite style's.


func speed() -> float:
	return 1.5


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("crunch_target", "target", {"nudge": 0.35})
	steps.on_foe("crunch_targetrocks", "target", {"delay": 0.13, "nudge": 0.35})
	steps.on_foe("crunch_targetspark", "target", {"delay": 0.13, "nudge": 0.35})
