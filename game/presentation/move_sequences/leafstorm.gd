extends "res://game/presentation/move_sequences/styles/mind.gd"
## Leaf Storm, in Cobblemon's own pieces; phases it has none for are the mind style's.


func speed() -> float:
	return 1.5


func fire(steps: SequenceSteps) -> void:
	steps.on_user("leafstorm_actorexcess1", "special", {"aim": true, "aim_at": "middle"})
	steps.on_user("leafstorm_actor", "special", {"aim": true, "aim_at": "middle", "delay": 0.07})


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("leafstorm_target")
