extends "res://game/presentation/move_sequences/styles/stream.gd"
## Water Gun, in Cobblemon's own pieces; phases it has none for are the stream style's.


func speed() -> float:
	return 1.5


func fire(steps: SequenceSteps) -> void:
	steps.on_user("watergun_spray", "special", {"aim": true})
	steps.on_user("watergun_actor", "special", {"aim": true, "delay": 0.01})


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("watergun_target")
	steps.on_foe("watergun_targetfoam")
