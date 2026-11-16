extends "res://game/presentation/move_sequences/styles/rush.gd"
## Quick Attack, in Cobblemon's own pieces; phases it has none for are the rush style's.


func speed() -> float:
	return 1.5


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("tackle_target", "target", {"nudge": 0.35})
	steps.on_foe("quickattack_targetsparks", "target", {"nudge": 0.35})
