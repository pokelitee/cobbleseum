extends "res://game/presentation/move_sequences/styles/rush.gd"
## Play Rough, in Cobblemon's own pieces; phases it has none for are the rush style's.


func speed() -> float:
	return 1.5


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("playrough_target", "target", {"nudge": 0.35})
