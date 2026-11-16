extends StyleSequence
## punch: a fist bursting on the foe, with sparks.


func hit(steps: SequenceSteps) -> void:
	super(steps)
	steps.on_foe("bulletpunch_target", "target", ACCENT)
	steps.on_foe("bulletpunch_targetsparks", "target", ACCENT)
