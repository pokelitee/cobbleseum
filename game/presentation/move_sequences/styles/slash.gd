extends StyleSequence
## slash: claw marks raked across the foe.


func hit(steps: SequenceSteps) -> void:
	super(steps)
	steps.on_foe("scratch_target", "target", ACCENT)
	steps.on_foe("scratch_targetsparks", "target", ACCENT)
	steps.on_foe("aerialace_targetcut1", "target", accent({"delay": 0.08}))
