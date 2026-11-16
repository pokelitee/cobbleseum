extends "res://game/presentation/move_sequences/styles/rush.gd"
## Pursuit, in Cobblemon's own pieces; phases it has none for are the rush style's.


func speed() -> float:
	return 1.5


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("pursuit_target", "target", {"nudge": 0.35})
	steps.on_foe("pursuit_targethit", "target", {"delay": 0.6, "nudge": 0.35})
	steps.on_foe("pursuit_targetdots", "target", {"delay": 0.6, "nudge": 0.35})
