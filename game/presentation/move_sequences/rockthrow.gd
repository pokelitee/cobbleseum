extends "res://game/presentation/move_sequences/styles/skyfall.gd"
## Rock Throw, in Cobblemon's own pieces; phases it has none for are the skyfall style's.


func speed() -> float:
	return 1.5


func fire(steps: SequenceSteps) -> void:
	steps.on_user("rockthrow_actor", "target", {"aim": true})


func flight(_steps: SequenceSteps) -> void:
	pass
