extends StyleSequence
## bolt: sparks crackling round the user, a bolt aimed at the foe, sparks on it.


func speed() -> float:
	return 1.5


func windup(steps: SequenceSteps) -> void:
	steps.on_user("thunderbolt_actorsparks", "middle", TINT)


func fire(steps: SequenceSteps) -> void:
	steps.on_user("thunderbolt_actor", "special", tinted({"aim": true}))


func hit(steps: SequenceSteps) -> void:
	super(steps)
	steps.on_foe("thunderbolt_targetsparks", "target", TINT)


func blast(steps: SequenceSteps) -> void:
	super(steps)
	steps.on_user("thunderbolt_actorbolts", "middle", TINT)
