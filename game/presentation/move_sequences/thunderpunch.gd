extends "res://game/presentation/move_sequences/styles/punch.gd"
## Thunder Punch, in Cobblemon's own pieces; phases it has none for are the punch style's.


func speed() -> float:
	return 1.5


func windup(steps: SequenceSteps) -> void:
	steps.on_user("thunderpunch_hand", "hand_primary")


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("thunderpunch_target", "target", {"nudge": 0.35})
