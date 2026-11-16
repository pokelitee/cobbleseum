extends StyleSequence
## erupt: the ground bursting up under the foe, throwing rocks.


func speed() -> float:
	return 1.3


func hit(steps: SequenceSteps) -> void:
	super(steps)
	steps.on_foe("bulldoze_targetfloor", "root", tinted({"aim": true, "aim_at": "root"}))
	steps.on_foe("eruption_targetrocks", "root", TINT)
