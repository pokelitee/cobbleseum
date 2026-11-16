extends "res://game/presentation/move_sequences/styles/skyfall.gd"
## Rock Slide, in Cobblemon's own pieces; phases it has none for are the skyfall style's.


func speed() -> float:
	return 1.5


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("rockslide_targetguide1", "root")
