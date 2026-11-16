extends "res://game/presentation/move_sequences/styles/strike.gd"
## Infestation, in Cobblemon's own pieces; phases it has none for are the strike style's.


func speed() -> float:
	return 1.5


func windup(steps: SequenceSteps) -> void:
	steps.on_user("infestation_actorground", "root")
	steps.on_user("infestation_actorflydisperse")


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("infestation_targetground", "root", {"nudge": 0.35})
	steps.on_foe("infestation_targetflyengulf", "middle", {"nudge": 0.35})
	steps.on_foe("infestation_targetswarm", "middle", {"delay": 0.2, "nudge": 0.35})
	steps.on_foe("infestation_targetsmallhits", "middle", {"delay": 0.2, "nudge": 0.35})
