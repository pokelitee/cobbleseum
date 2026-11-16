extends StyleSequence
## beam: a charge at the mouth, a beam aimed at the foe, and a burst where it lands.


func speed() -> float:
	return 1.6


func windup(steps: SequenceSteps) -> void:
	steps.on_user("aurorabeam_charge", "special", TINT)


func fire(steps: SequenceSteps) -> void:
	steps.on_user("aurorabeam_actorpilot", "special", tinted({"aim": true}))


func hit(steps: SequenceSteps) -> void:
	super(steps)
	steps.on_foe("aurorabeam_targetburst", "target", TINT)
