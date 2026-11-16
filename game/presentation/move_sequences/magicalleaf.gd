extends "res://game/presentation/move_sequences/styles/mind.gd"
## Magical Leaf, in Cobblemon's own pieces; phases it has none for are the mind style's.


func speed() -> float:
	return 1.5


func fire(steps: SequenceSteps) -> void:
	steps.on_user("magicalleaf_actor", "root", {"aim": true, "aim_at": "middle"})
	steps.on_user("magicalleaf_actorexcess")


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("magicalleaf_target")
