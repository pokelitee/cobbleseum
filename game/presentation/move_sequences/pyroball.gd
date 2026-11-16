extends "res://game/presentation/move_sequences/styles/bullet.gd"
## Pyro Ball, in Cobblemon's own pieces; phases it has none for are the bullet style's.


func speed() -> float:
	return 1.5


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("flamethrower_targetburst")
