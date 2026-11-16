extends "res://game/presentation/move_sequences/styles/status.gd"
## Nasty Plot, in Cobblemon's own pieces; phases it has none for are the status style's.


func speed() -> float:
	return 1.5


func windup(steps: SequenceSteps) -> void:
	steps.on_user("nastyplot_actortrailsmall", "top", {"keep": true})
	steps.on_user("nastyplot_actortraillarge", "top", {"delay": 0.07, "keep": true})
	steps.on_user("nastyplot_actorcloud", "top", {"delay": 0.13, "keep": true})
	steps.on_user("nastyplot_actorexclamation", "top", {"delay": 0.6, "keep": true})
