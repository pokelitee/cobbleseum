extends "res://game/presentation/move_sequences/styles/rush.gd"
## Horn Attack, in Cobblemon's own pieces; phases it has none for are the rush style's.


func speed() -> float:
	return 1.5


func windup(steps: SequenceSteps) -> void:
	steps.on_user("hornattack_actor", "target", {"aim": true})


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("pound_target", "target", {"nudge": 0.35})
	steps.on_foe("pound_targetsparks", "target", {"nudge": 0.35})
