extends "res://game/presentation/move_sequences/styles/stream.gd"
## Flame Burst, in Cobblemon's own pieces; phases it has none for are the stream style's.


func speed() -> float:
	return 1.5


func fire(steps: SequenceSteps) -> void:
	steps.on_user("flameburst_actorfling", "special", {"aim": true})
	steps.on_user("flameburst_actor", "special", {"aim": true, "delay": 0.01})


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("flameburst_target")
