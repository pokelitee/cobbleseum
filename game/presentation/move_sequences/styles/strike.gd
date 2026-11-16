extends StyleSequence
## strike: a claw-like swipe and sparks across the foe.


func hit(steps: SequenceSteps) -> void:
	super(steps)
	steps.on_foe("scratch_target", "target", ACCENT)
	steps.on_foe("tackle_targetsparks", "target", ACCENT)
