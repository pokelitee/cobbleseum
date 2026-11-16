extends "res://game/presentation/move_sequences/styles/orb.gd"
## Night Shade, in Cobblemon's own pieces; phases it has none for are the orb style's.


func speed() -> float:
	return 1.5


func fire(steps: SequenceSteps) -> void:
	steps.on_user("nightshade_actorpulse1", "special", {"aim": true})
	steps.on_user("nightshade_actor", "special", {"aim": true})


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("nightshade_target")
	steps.on_user("nightshade_actorpulse2", "special", {"aim": true})
