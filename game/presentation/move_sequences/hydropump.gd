extends "res://game/presentation/move_sequences/styles/stream.gd"
## Hydro Pump, in Cobblemon's own pieces; phases it has none for are the stream style's.


func speed() -> float:
	return 1.5


func fire(steps: SequenceSteps) -> void:
	steps.on_user("hydropump_actorpulse", "special", {"aim": true})
	steps.on_user("hydropump_actor", "special", {"aim": true})
	steps.on_user("hydropump_actor", "special", {"aim": true, "delay": 0.02})


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("hydropump_target")
	steps.on_foe("hydropump_targetburst", "target", {"delay": 0.37})
