extends MoveSequence
## Ice Beam: a charge at the mouth, a beam aimed at the foe, frost building on it, then shards.


func speed() -> float:
	return 1.6


func windup(steps: SequenceSteps) -> void:
	steps.on_user("icebeam_actoremit", "special")


func fire(steps: SequenceSteps) -> void:
	steps.on_user("icebeam_actorpilot", "special", {"aim": true})


func hit(steps: SequenceSteps) -> void:
	steps.on_foe("icebeam_target")
	steps.on_foe("icebeam_targetbuild", "middle")
	steps.on_foe("icebeam_targetburst", "target", {"delay": 0.5})
	steps.on_foe("icebeam_targetfrost", "target", {"delay": 0.75})
