extends "res://game/presentation/move_sequences/styles/status.gd"
## Will-O-Wisp, in Cobblemon's own pieces; phases it has none for are the status style's.


func speed() -> float:
	return 1.5


func fire(steps: SequenceSteps) -> void:
	steps.on_user("willowisp_actor", "special", {"aim": true})


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.on_foe("willowisp_target")
