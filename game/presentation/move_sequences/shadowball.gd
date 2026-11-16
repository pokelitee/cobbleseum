extends MoveSequence
## Shadow Ball: dark energy gathering at the mouth, a flaring blob riding the projectile, and a
## ghostly splash on the foe.


func speed() -> float:
	return 1.4


func windup(steps: SequenceSteps) -> void:
	steps.on_user("shadowball_actorcharge", "special")


func flight(steps: SequenceSteps) -> void:
	steps.on_user("shadowball_actorblob", "middle", {"max": 3.0})
	steps.on_user("shadowball_actorflaring", "middle", {"max": 3.0})


func hit(steps: SequenceSteps) -> void:
	steps.on_foe("shadowball_targetimpact", "target", {"max": 0.4})
	steps.on_foe("impact_ghost")
