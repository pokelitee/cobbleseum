extends "res://game/presentation/move_sequences/styles/bullet.gd"
## Acid Spray, in Cobblemon's own pieces; phases it has none for are the bullet style's.


func speed() -> float:
	return 1.5


func fire(steps: SequenceSteps) -> void:
	steps.on_user("acidspray_actorfling", "special", {"aim": true})
	steps.on_user("acidspray_actor", "special", {"aim": true})


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("acidspray_target")
