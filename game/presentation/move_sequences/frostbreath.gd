extends "res://game/presentation/move_sequences/styles/stream.gd"
## Frost Breath, in Cobblemon's own pieces; phases it has none for are the stream style's.


func speed() -> float:
	return 1.5


func fire(steps: SequenceSteps) -> void:
	steps.on_user("frostbreath_actor", "special", {"aim": true, "aim_at": "middle"})
	steps.on_user("frostbreath_actorsparkle", "special", {"aim": true, "aim_at": "middle"})


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("frostbreath_target")
