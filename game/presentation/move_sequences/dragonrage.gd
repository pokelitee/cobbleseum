extends "res://game/presentation/move_sequences/styles/orb.gd"
## Dragon Rage, in Cobblemon's own pieces; phases it has none for are the orb style's.


func speed() -> float:
	return 1.5


func fire(steps: SequenceSteps) -> void:
	steps.on_user("dragonrage_actorburst", "special", {"aim": true})
	steps.on_user("dragonrage_actor", "special", {"aim": true, "delay": 0.01})


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("dragonrage_target")
