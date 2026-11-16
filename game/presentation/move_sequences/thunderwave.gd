extends "res://game/presentation/move_sequences/styles/status.gd"
## Thunder Wave, in Cobblemon's own pieces; phases it has none for are the status style's.


func speed() -> float:
	return 1.5


func fire(steps: SequenceSteps) -> void:
	steps.on_user("thunderwave_launch1", "special_attack", {"aim": true})
	steps.on_user("thunderwave_actor", "special_attack", {"aim": true})
	steps.on_user("thunderwave_launch2", "special_attack", {"aim": true, "delay": 0.03})


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.on_foe("thunderwave_impact1")
	steps.on_foe("thunderwave_impact2", "target", {"delay": 0.07})
	steps.on_foe("thunderwave_sparking", "target", {"delay": 0.07})
	steps.on_foe("thunderwave_impact3", "target", {"delay": 0.13})
