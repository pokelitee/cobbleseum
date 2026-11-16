extends StyleSequence
## kick: a low stamping burst on the foe.


func hit(steps: SequenceSteps) -> void:
	super(steps)
	steps.on_foe("stomp_target_impact1", "middle", ACCENT)
	steps.on_foe("stomp_target_impact2", "middle", accent({"delay": 0.1}))
