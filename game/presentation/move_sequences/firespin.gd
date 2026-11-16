extends "res://game/presentation/move_sequences/styles/stream.gd"
## Fire Spin, in Cobblemon's own pieces; phases it has none for are the stream style's.


func speed() -> float:
	return 1.5


func fire(steps: SequenceSteps) -> void:
	steps.on_user("firespin_actorburst", "special", {"aim": true, "aim_at": "root"})
	steps.on_user("firespin_actor", "special", {"aim": true, "aim_at": "root", "delay": 0.01})


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("firespin_targetburst", "root")
	steps.on_foe("firespin_target", "root")
