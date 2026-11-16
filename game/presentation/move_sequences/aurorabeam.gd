extends "res://game/presentation/move_sequences/styles/beam.gd"
## Aurora Beam, in Cobblemon's own pieces; phases it has none for are the beam style's.


func speed() -> float:
	return 1.5


func windup(steps: SequenceSteps) -> void:
	steps.on_user("aurorabeam_charge", "special")


func fire(steps: SequenceSteps) -> void:
	steps.on_user("aurorabeam_actorpilot", "special", {"aim": true})


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("aurorabeam_target")
	steps.on_foe("aurorabeam_targetburst", "target", {"delay": 0.33})
