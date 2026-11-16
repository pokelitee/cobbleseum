extends "res://game/presentation/move_sequences/styles/strike.gd"
## Seismic Toss, in Cobblemon's own pieces; phases it has none for are the strike style's.


func speed() -> float:
	return 1.5


func windup(steps: SequenceSteps) -> void:
	steps.on_user("seismictoss_actor")


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("seismictoss_actorgrab", "target", {"nudge": 0.35})
	steps.on_foe("seismictoss_actorin", "target", {"nudge": 0.35})
