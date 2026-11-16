extends "res://game/presentation/move_sequences/styles/punch.gd"
## Drain Punch, in Cobblemon's own pieces; phases it has none for are the punch style's.


func speed() -> float:
	return 1.5


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("drainpunch_target", "target", {"nudge": 0.35})
	steps.on_user("drainpunch_actor", "target", {"aim": true, "delay": 0.03})
	steps.on_user("megadrain_actorhealtimer", "middle", {"delay": 0.03})
