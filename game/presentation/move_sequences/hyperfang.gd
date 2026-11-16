extends "res://game/presentation/move_sequences/styles/bite.gd"
## Hyper Fang, in Cobblemon's own pieces; phases it has none for are the bite style's.


func speed() -> float:
	return 1.5


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("hyperfang_target", "target", {"nudge": 0.35})
	steps.on_foe("hyperfang_targetspark", "target", {"delay": 0.1, "nudge": 0.35})
	steps.on_foe("hyperfang_targetdot", "target", {"delay": 0.1, "nudge": 0.35})
