extends "res://game/presentation/move_sequences/styles/status.gd"
## Cotton Guard, in Cobblemon's own pieces; phases it has none for are the status style's.


func speed() -> float:
	return 1.5


func windup(steps: SequenceSteps) -> void:
	steps.on_user("cottonguard", "middle", {"keep": true})
