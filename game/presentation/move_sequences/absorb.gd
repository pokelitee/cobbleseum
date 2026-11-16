extends "res://game/presentation/move_sequences/styles/stream.gd"
## Absorb, in Cobblemon's own pieces; phases it has none for are the stream style's.


func speed() -> float:
	return 1.5


func fire(_steps: SequenceSteps) -> void:
	pass


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("absorb_actorhit")
	steps.on_user("absorb_actor", "special", {"aim": true})
	steps.on_user("absorb_actorhealtimer")
