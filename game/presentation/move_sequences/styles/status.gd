extends StyleSequence
## status: moves that deal no damage glimmer as the user winds up; what they do shows
## as the battle's own cue (a stat change, a status, a heal).


func windup(steps: SequenceSteps) -> void:
	steps.on_user("alphaboost_actorsparks", "middle", TINT)


func hit(_steps: SequenceSteps) -> void:
	pass


func blast(_steps: SequenceSteps) -> void:
	pass
