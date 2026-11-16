extends "res://game/presentation/move_sequences/styles/strike.gd"
## Dragon Claw, in Cobblemon's own pieces; phases it has none for are the strike style's.


func speed() -> float:
	return 1.5


func windup(steps: SequenceSteps) -> void:
	steps.on_user("dragonclaw_aura")
	steps.on_user("dragonclaw_hand", "hand_primary")


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("dragonclaw_target", "target", {"nudge": 0.35})
