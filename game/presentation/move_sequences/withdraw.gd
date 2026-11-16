extends "res://game/presentation/move_sequences/styles/status.gd"
## Withdraw, in Cobblemon's own pieces; phases it has none for are the status style's.


func speed() -> float:
	return 1.5


func windup(steps: SequenceSteps) -> void:
	steps.on_user("withdraw_actor1", "middle", {"keep": true})
	steps.on_user("withdraw_actorbubbles", "middle", {"delay": 0.33, "keep": true})
