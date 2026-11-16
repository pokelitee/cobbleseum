extends "res://game/presentation/move_sequences/styles/stream.gd"
## Bubble, in Cobblemon's own pieces; phases it has none for are the stream style's.


func speed() -> float:
	return 1.5


func blast(steps: SequenceSteps) -> void:
	steps.on_user("bubble_actor", "special", {"aim": true})
