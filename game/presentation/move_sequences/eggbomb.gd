extends "res://game/presentation/move_sequences/styles/bullet.gd"
## Egg Bomb, in Cobblemon's own pieces; phases it has none for are the bullet style's.


func speed() -> float:
	return 1.5


func fire(steps: SequenceSteps) -> void:
	steps.on_user("eggbomb_actoregg", "special", {"aim": true})


func flight(_steps: SequenceSteps) -> void:
	pass
