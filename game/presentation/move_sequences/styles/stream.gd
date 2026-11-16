extends StyleSequence
## stream: breath or spray pouring from the mouth at the foe, splashing over it.


func speed() -> float:
	return 1.4


func fire(steps: SequenceSteps) -> void:
	steps.on_user("flamethrower_actor", "special", tinted({"aim": true, "max": 0.6}))


func hit(steps: SequenceSteps) -> void:
	super(steps)
	steps.on_foe("flamethrower_targetburst", "target", TINT)
