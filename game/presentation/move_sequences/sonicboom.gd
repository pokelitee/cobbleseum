extends "res://game/presentation/move_sequences/styles/orb.gd"
## Sonic Boom, in Cobblemon's own pieces; phases it has none for are the orb style's.


func speed() -> float:
	return 1.5


func fire(steps: SequenceSteps) -> void:
	steps.on_user("sonicboom_actor", "special", {"aim": true})


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("sonicboom_target")
