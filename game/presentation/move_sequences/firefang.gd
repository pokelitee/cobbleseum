extends "res://game/presentation/move_sequences/styles/bite.gd"
## Fire Fang, in Cobblemon's own pieces; phases it has none for are the bite style's.


func speed() -> float:
	return 1.5


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("firefang_target", "target", {"nudge": 0.35})
	steps.on_foe("firefang_targetspark", "target", {"delay": 0.1, "nudge": 0.35})
	steps.on_foe("firefang_targetburst", "target", {"delay": 0.1, "nudge": 0.35})
