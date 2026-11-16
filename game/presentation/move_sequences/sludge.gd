extends "res://game/presentation/move_sequences/styles/stream.gd"
## Sludge, in Cobblemon's own pieces; phases it has none for are the stream style's.


func speed() -> float:
	return 1.5


func fire(steps: SequenceSteps) -> void:
	steps.on_user("sludge_actorfling", "special", {"aim": true})
	steps.on_user("sludge_actor", "special", {"aim": true})


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("sludge_target")
