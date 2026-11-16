extends "res://game/presentation/move_sequences/styles/wind.gd"
## Fairy Wind, in Cobblemon's own pieces; phases it has none for are the wind style's.


func speed() -> float:
	return 1.5


func fire(steps: SequenceSteps) -> void:
	steps.on_user("fairywind_actor", "special_attack", {"aim": true})


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("fairywind_target")
	steps.on_foe("fairywind_targethit")
