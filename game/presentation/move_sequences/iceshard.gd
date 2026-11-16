extends "res://game/presentation/move_sequences/styles/orb.gd"
## Ice Shard, in Cobblemon's own pieces; phases it has none for are the orb style's.


func speed() -> float:
	return 1.5


func fire(steps: SequenceSteps) -> void:
	steps.on_user("iceshard_actor", "special", {"aim": true})


func flight(_steps: SequenceSteps) -> void:
	pass
