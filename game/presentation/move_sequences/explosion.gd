extends "res://game/presentation/move_sequences/styles/explosion.gd"
## Explosion, in Cobblemon's own pieces; phases it has none for are the explosion style's.


func speed() -> float:
	return 1.5


func blast(steps: SequenceSteps) -> void:
	steps.on_user("explosion_actororbs")
	steps.on_user("explosion_actorboom", "middle", {"delay": 0.6})
	steps.on_user("explosion_actorfire", "root", {"delay": 0.6})
	steps.on_user("explosion_actorbigring", "root", {"delay": 0.6})
	steps.on_user("explosion_actorfloorscorch", "middle", {"delay": 0.6})
