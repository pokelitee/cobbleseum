extends "res://game/presentation/move_sequences/styles/sound.gd"
## Disarming Voice, in Cobblemon's own pieces; phases it has none for are the sound style's.


func speed() -> float:
	return 1.5


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("disarmingvoice_target")


func blast(steps: SequenceSteps) -> void:
	steps.on_user("disarmingvoice_actor1", "mouth", {"aim": true})
	steps.on_user("disarmingvoice_actorhearts", "mouth", {"aim": true})
	steps.on_user("disarmingvoice_actor2", "mouth", {"aim": true})
