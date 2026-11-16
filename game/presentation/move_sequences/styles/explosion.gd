extends StyleSequence
## explosion: a flash and a burst of smoke and debris.


func speed() -> float:
	return 1.3


func fire(steps: SequenceSteps) -> void:
	_boom(steps)


func blast(steps: SequenceSteps) -> void:
	super(steps)
	_boom(steps)


func _boom(steps: SequenceSteps) -> void:
	steps.on_user("explosion_burst_flash", "middle", TINT)
	steps.on_user("explosion_actorboom", "middle", TINT)
