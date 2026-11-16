extends "res://game/presentation/move_sequences/styles/rush.gd"
## Flame Charge, in Cobblemon's own pieces; phases it has none for are the rush style's.


func speed() -> float:
	return 1.5


func windup(steps: SequenceSteps) -> void:
	steps.on_user("flamecharge_actor")
	steps.on_user("flamecharge_actorspiral", "root", {"delay": 0.07})


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("flamecharge_target", "target", {"nudge": 0.35})
