extends "res://game/presentation/move_sequences/styles/status.gd"
## String Shot: a spray of silk from the mouth, then threads wrapping the foe. Cobblemon's
## single long thread is centred on the mouth, so half of it would trail behind the user.


func speed() -> float:
	return 1.5


func fire(steps: SequenceSteps) -> void:
	steps.on_user("stringshot_actorspray", "mouth", {"aim": true, "aim_at": "middle"})


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.on_foe("stringshot_target1", "middle")
	steps.on_foe("stringshot_target2", "middle")
	steps.on_foe("stringshot_targetwrap", "middle")
