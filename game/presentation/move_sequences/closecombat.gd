extends MoveSequence
## Close Combat: dash lines on the wind-up, then a flurry of swipes and bursts on the foe.


func speed() -> float:
	return 1.5


func windup(steps: SequenceSteps) -> void:
	steps.on_user("closecombat_dashlines")


func hit(steps: SequenceSteps) -> void:
	steps.on_user("closecombat_actor")
	steps.on_foe("closecombat_target", "target", {"face_camera": true})
	steps.on_foe("closecombat_target2", "target", {"face_camera": true, "delay": 0.2})
