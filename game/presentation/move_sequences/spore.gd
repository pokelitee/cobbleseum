extends "res://game/presentation/move_sequences/styles/status.gd"
## Spore, in Cobblemon's own pieces; phases it has none for are the status style's.


func speed() -> float:
	return 1.5


func windup(steps: SequenceSteps) -> void:
	steps.on_user("spore", "target")
	steps.on_user("spore_cloud", "target")


func hit(steps: SequenceSteps) -> void:
	steps.on_foe("spore_land", "root")
