extends "res://game/presentation/move_sequences/styles/orb.gd"
## Razor Leaf, in Cobblemon's own pieces; phases it has none for are the orb style's.


func speed() -> float:
	return 1.5


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("razorleaf_target")


func blast(steps: SequenceSteps) -> void:
	steps.on_user("razorleaf_actor", "root", {"aim": true, "aim_at": "middle"})
	steps.on_user("razorleaf_actorexcess")
