extends "res://game/presentation/move_sequences/styles/status.gd"
## Toxic, in Cobblemon's own pieces; phases it has none for are the status style's.


func speed() -> float:
	return 1.5


func hit(steps: SequenceSteps) -> void:
	steps.on_foe("toxpoison_actor")
