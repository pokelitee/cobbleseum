extends "res://game/presentation/move_sequences/styles/bolt.gd"
## Thunder Shock, in Cobblemon's own pieces; phases it has none for are the bolt style's.


func speed() -> float:
	return 1.5


func windup(steps: SequenceSteps) -> void:
	steps.on_user("thundershock_actorsparks")
	steps.on_user("thundershock_actorbolts", "root")


func fire(steps: SequenceSteps) -> void:
	steps.on_user("thundershock_actor", "target", {"aim": true})


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("thundershock_target")
	steps.on_foe("thundershock_targetbolts")
	steps.on_foe("thundershock_targetimpact")
