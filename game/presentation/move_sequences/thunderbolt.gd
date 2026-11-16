extends "res://game/presentation/move_sequences/styles/bolt.gd"
## Thunderbolt, in Cobblemon's own pieces; phases it has none for are the bolt style's.


func speed() -> float:
	return 1.5


func windup(steps: SequenceSteps) -> void:
	steps.on_user("thunderbolt_actorsparks")
	steps.on_user("thunderbolt_actorbolts")


func fire(steps: SequenceSteps) -> void:
	steps.on_user("thunderbolt_actor", "target", {"aim": true})


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("thunderbolt_target")
