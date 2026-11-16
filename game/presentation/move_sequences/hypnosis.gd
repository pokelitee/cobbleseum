extends "res://game/presentation/move_sequences/styles/status.gd"
## Hypnosis, in Cobblemon's own pieces; phases it has none for are the status style's.


func speed() -> float:
	return 1.5


func fire(steps: SequenceSteps) -> void:
	steps.on_user("hypnosis_actor", "target", {"aim": true})


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.on_foe("hypnosis_targetimpact")
	steps.on_foe("hypnosis_target")
