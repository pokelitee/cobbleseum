extends MoveSequence
## Swords Dance: swords circling the user, running on past the wind-up.


func speed() -> float:
	return 1.5


func windup(steps: SequenceSteps) -> void:
	steps.on_user("swordsdance_actor", "middle", {"keep": true})
