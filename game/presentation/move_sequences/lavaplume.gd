extends "res://game/presentation/move_sequences/styles/stream.gd"
## Lava Plume, in Cobblemon's own pieces; phases it has none for are the stream style's.


func speed() -> float:
	return 1.5


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("lavaplume_target", "root")


func blast(steps: SequenceSteps) -> void:
	steps.on_user("lavaplume_actor", "middle", {"aim": true, "aim_at": "root"})
