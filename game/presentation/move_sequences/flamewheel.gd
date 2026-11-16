extends "res://game/presentation/move_sequences/styles/strike.gd"
## Flame Wheel, in Cobblemon's own pieces; phases it has none for are the strike style's.


func speed() -> float:
	return 1.5


func windup(steps: SequenceSteps) -> void:
	steps.on_user("flamewheel_actor")


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("flamewheel_target", "target", {"nudge": 0.35})
	steps.on_foe("ember_targetlinger", "target", {"nudge": 0.35})
