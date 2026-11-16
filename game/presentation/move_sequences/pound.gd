extends "res://game/presentation/move_sequences/styles/strike.gd"
## Pound, in Cobblemon's own pieces; phases it has none for are the strike style's.


func speed() -> float:
	return 1.5


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("pound_target", "target", {"nudge": 0.35})
	steps.on_foe("pound_targetsparks", "target", {"nudge": 0.35})
