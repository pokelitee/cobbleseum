extends StyleSequence
## bullet: a small, fast shot.


func speed() -> float:
	return 1.4


func fire(steps: SequenceSteps) -> void:
	steps.on_user("iceshard_actor", "special", tinted({"aim": true}))


func flight(steps: SequenceSteps) -> void:
	steps.on_user("shadowball_actorflaring", "middle", tinted({"max": 3.0, "scale": 0.5}))


func hit(steps: SequenceSteps) -> void:
	super(steps)
	steps.on_foe("pound_targetsparks", "target", TINT)
