extends StyleSequence
## bite: fangs snapping shut on the foe, with a spark.


func hit(steps: SequenceSteps) -> void:
	super(steps)
	steps.on_foe("bite_target", "target", ACCENT)
	steps.on_foe("bite_targetspark", "target", ACCENT)
