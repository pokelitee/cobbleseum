extends "res://game/presentation/move_sequences/styles/wind.gd"
## Blizzard, in Cobblemon's own pieces; phases it has none for are the wind style's.


func speed() -> float:
	return 1.5


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("blizzard_targetswirl", "middle")
	steps.on_foe("blizzard_target", "middle", {"aim": true, "aim_at": "middle", "delay": 0.57})


func blast(steps: SequenceSteps) -> void:
	steps.on_user("blizzard_actor", "root", {"aim": true, "aim_at": "middle"})
