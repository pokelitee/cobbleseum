extends "res://game/presentation/move_sequences/styles/status.gd"
## Supersonic, in Cobblemon's own pieces; phases it has none for are the status style's.


func speed() -> float:
	return 1.5


func fire(steps: SequenceSteps) -> void:
	steps.on_user("supersonic_launch", "special_attack")
	steps.on_user("supersonic_actor", "special_attack", {"aim": true})


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.on_foe("supersonic_impact1")
