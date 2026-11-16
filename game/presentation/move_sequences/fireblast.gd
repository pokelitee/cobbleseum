extends "res://game/presentation/move_sequences/styles/orb.gd"
## Fire Blast, in Cobblemon's own pieces; phases it has none for are the orb style's.


func speed() -> float:
	return 1.5


func fire(steps: SequenceSteps) -> void:
	steps.on_user("fireblast_actorshoot", "special")
	steps.on_user("fireblast_actor1", "special", {"aim": true})
	steps.on_user("fireblast_actor2", "special", {"aim": true})


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("fireblast_target")
	steps.on_foe("daimonji1", "target", {"delay": 0.02})
	steps.on_foe("daimonji2", "target", {"delay": 0.02})
	steps.on_foe("daimonji3", "target", {"delay": 0.02})
	steps.on_foe("daimonji4", "target", {"delay": 0.02})
