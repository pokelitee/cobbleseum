extends StyleSequence
## pulse: a ring of energy riding the projectile, splashing on the foe.


func speed() -> float:
	return 1.4


func windup(steps: SequenceSteps) -> void:
	steps.on_user("psybeam_charge", "special", TINT)


func fire(steps: SequenceSteps) -> void:
	steps.on_user("leafstorm_actorwind", "special", tinted({"aim": true, "scale": 1.8}))


func flight(steps: SequenceSteps) -> void:
	steps.on_user("waterpulse_actorring", "middle", tinted({"max": 3.0}))


func hit(steps: SequenceSteps) -> void:
	super(steps)
	steps.on_foe("waterpulse_targetsplash", "target", TINT)
