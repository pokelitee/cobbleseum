extends StyleSequence
## orb: energy gathering at the mouth, then a flaring ball riding the projectile.


func speed() -> float:
	return 1.4


func windup(steps: SequenceSteps) -> void:
	steps.on_user("aurorabeam_charge", "special", TINT)


func fire(steps: SequenceSteps) -> void:
	steps.on_user("mysticalfire_actorshot", "special", tinted({"aim": true}))


func flight(steps: SequenceSteps) -> void:
	steps.on_user("shadowball_actorflaring", "middle", tinted({"max": 3.0}))


func hit(steps: SequenceSteps) -> void:
	super(steps)
	steps.on_foe("shadowball_targetimpact", "target", tinted({"max": 0.4}))
