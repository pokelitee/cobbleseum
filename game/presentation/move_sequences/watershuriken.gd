extends "res://game/presentation/move_sequences/styles/mind.gd"
## Water Shuriken, in Cobblemon's own pieces; phases it has none for are the mind style's.


func speed() -> float:
	return 1.5


func fire(steps: SequenceSteps) -> void:
	steps.on_user("watershuriken_actoralt", "hand_primary", {"aim": true})


func flight(_steps: SequenceSteps) -> void:
	pass
