extends "res://game/presentation/move_sequences/styles/strike.gd"
## Lick, in Cobblemon's own pieces; phases it has none for are the strike style's.


func speed() -> float:
	return 1.5


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("lick_target", "target", {"nudge": 0.35})
	steps.on_foe("lick_targetsplash", "target", {"delay": 0.1, "nudge": 0.35})
	steps.on_foe("lick_targetdrip", "target", {"delay": 0.1, "nudge": 0.35})
