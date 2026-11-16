extends "res://game/presentation/move_sequences/styles/stream.gd"
## Acid, in Cobblemon's own pieces; phases it has none for are the stream style's.


func speed() -> float:
	return 1.5


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("acid_target")


func blast(steps: SequenceSteps) -> void:
	steps.on_user("acid_actorfling", "special", {"aim": true})
	steps.on_user("acid_actor", "special", {"aim": true})
