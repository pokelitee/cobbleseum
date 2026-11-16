extends StyleSequence
## skyfall: rocks falling onto the foe and dust where they land.


func speed() -> float:
	return 1.4


func hit(steps: SequenceSteps) -> void:
	super(steps)
	steps.on_foe("rockslide_target", "top", TINT)
	steps.on_foe("rockslide_targetdust", "root", tinted({"delay": 0.2}))
