extends "res://game/presentation/move_sequences/styles/mind.gd"
## Confusion, in Cobblemon's own pieces; phases it has none for are the mind style's.


func speed() -> float:
	return 1.5


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("confusion_target")
	steps.on_foe("confusion_impact", "target", {"delay": 0.6})
	steps.on_foe("confusion_impactdots", "target", {"delay": 0.6})
	steps.on_user("confusion_actorglint", "root")
	steps.on_user("confusion_actor", "root")
