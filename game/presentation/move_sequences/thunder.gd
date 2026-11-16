extends "res://game/presentation/move_sequences/styles/skyfall.gd"
## Thunder: sparks and a crackling ring on the user, a storm cloud gathering over the foe as the
## move is released, and the bolt striking it on the hit. Cobblemon's own timeline waits over a
## second between cloud and bolt, so the cloud moves up to the release instead.


func speed() -> float:
	return 1.5


func windup(steps: SequenceSteps) -> void:
	steps.on_user("thunderbolt_actorsparks")
	steps.on_user("thundershock_actorbolts", "root")
	steps.on_user("thunder_actorring", "root", {"delay": 0.2})


func fire(steps: SequenceSteps) -> void:
	steps.on_foe("thunder_targetcloud", "root")


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.on_foe("thunder_target", "root")
	steps.on_foe("thunder_actorfloorscorch", "middle")
	steps.on_foe("thunder_actorsmoke", "root")
	steps.impact()
