extends StyleSequence
## quake: the ground heaving under the foe (area moves add the quake ring).


func speed() -> float:
	return 1.3


func hit(steps: SequenceSteps) -> void:
	super(steps)
	steps.on_foe("bulldoze_targetfloor", "root", tinted({"aim": true, "aim_at": "root"}))
