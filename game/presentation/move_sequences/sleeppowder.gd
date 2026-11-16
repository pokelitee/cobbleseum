extends "res://game/presentation/move_sequences/styles/status.gd"
## Sleep Powder, in Cobblemon's own pieces; phases it has none for are the status style's.


func speed() -> float:
	return 1.5


func windup(steps: SequenceSteps) -> void:
	steps.on_user("sleeppowder", "target")
	steps.on_user("sleeppowder_cloud", "target")


func hit(steps: SequenceSteps) -> void:
	steps.on_foe("sleeppowder_land", "root")
