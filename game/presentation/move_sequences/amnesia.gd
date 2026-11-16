extends "res://game/presentation/move_sequences/styles/status.gd"
## Amnesia, in Cobblemon's own pieces; phases it has none for are the status style's.


func speed() -> float:
	return 1.5


func windup(steps: SequenceSteps) -> void:
	steps.on_user("amnesia_actortrailsmall", "top", {"keep": true})
	steps.on_user("amnesia_actortraillarge", "top", {"delay": 0.07, "keep": true})
	steps.on_user("amnesia_actorcloud", "top", {"delay": 0.13, "keep": true})
	steps.on_user("amnesia_actorquestion", "top", {"delay": 0.6, "keep": true})
