extends "res://game/presentation/move_sequences/styles/status.gd"
## Scary Face, in Cobblemon's own pieces; phases it has none for are the status style's.


func speed() -> float:
	return 1.5


func fire(steps: SequenceSteps) -> void:
	steps.on_user("scaryface_gleam", "eye")
	steps.on_user("scaryface_actor", "face", {"delay": 0.52})
