extends MoveSequence
## Bulldoze: a quake ring and sparks around the user, and the ground heaving under the foe.


func speed() -> float:
	return 1.3


func blast(steps: SequenceSteps) -> void:
	steps.on_user("bulldoze_actorquake", "root")
	steps.on_user("bulldoze_actorspark", "root")


func hit(steps: SequenceSteps) -> void:
	steps.on_foe("bulldoze_targetfloor", "root", {"aim": true, "aim_at": "root"})
