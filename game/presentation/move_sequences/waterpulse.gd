extends "res://game/presentation/move_sequences/styles/pulse.gd"
## Water Pulse, in Cobblemon's own pieces; phases it has none for are the pulse style's.


func speed() -> float:
	return 1.5


func windup(steps: SequenceSteps) -> void:
	steps.on_user("waterpulse_actorsuds", "root")


func fire(steps: SequenceSteps) -> void:
	steps.on_user("waterpulse_actor", "special", {"aim": true})


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("waterpulse_target")
	steps.on_foe("waterpulse_targetsplash")
	steps.on_foe("waterpulse_actorsuds", "root")
