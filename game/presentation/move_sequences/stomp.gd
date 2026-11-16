extends "res://game/presentation/move_sequences/styles/kick.gd"
## Stomp, in Cobblemon's own pieces; phases it has none for are the kick style's.


func speed() -> float:
	return 1.5


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("stomp_target_impact1", "root", {"aim": true, "aim_at": "root", "nudge": 0.35})
	steps.on_foe("stomp_target_impact2", "root", {"aim": true, "aim_at": "root", "nudge": 0.35})
