extends "res://game/presentation/move_sequences/styles/wind.gd"
## Icy Wind, in Cobblemon's own pieces; phases it has none for are the wind style's.


func speed() -> float:
	return 1.5


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("icywind_targetfrost", "middle")
	steps.on_foe("icywind_target", "middle", {"delay": 0.57})


func blast(steps: SequenceSteps) -> void:
	steps.on_user("icywind_actorpilot", "special", {"aim": true})
