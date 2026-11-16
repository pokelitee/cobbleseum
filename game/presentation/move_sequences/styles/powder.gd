extends StyleSequence
## powder: a cloud of motes drifting onto the foe.


func speed() -> float:
	return 1.4


func fire(steps: SequenceSteps) -> void:
	steps.on_user("powder_particles", "special", tinted({"aim": true}))


func hit(steps: SequenceSteps) -> void:
	super(steps)
	steps.on_foe("stunspore_landcloud", "middle", TINT)
