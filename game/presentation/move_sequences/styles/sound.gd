extends StyleSequence
## sound: waves rippling from the user to the foe.


func speed() -> float:
	return 1.4


func windup(steps: SequenceSteps) -> void:
	steps.on_user("sing_actor", "mouth", TINT)


func fire(steps: SequenceSteps) -> void:
	steps.on_user("disarmingvoice_actor1", "mouth", tinted({"aim": true, "scale": 2.0}))


func hit(steps: SequenceSteps) -> void:
	super(steps)
	steps.on_foe("supersonic_impact1", "target", tinted({"scale": 1.6}))
