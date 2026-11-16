extends StyleSequence
## mind: a psychic glow gathering, then waves wrapping the foe.


func speed() -> float:
	return 1.4


func windup(steps: SequenceSteps) -> void:
	steps.on_user("psybeam_charge", "special", TINT)


func hit(steps: SequenceSteps) -> void:
	super(steps)
	steps.on_foe("psychic_target", "middle", TINT)
	steps.on_foe("psychic_impact", "target", TINT)
