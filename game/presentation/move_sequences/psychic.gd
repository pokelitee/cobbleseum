extends "res://game/presentation/move_sequences/styles/mind.gd"
## Psychic: a psychic aura rising round the user, then waves gripping the foe and bursting.
## Cobblemon's burst comes a second after the grip; here it follows quickly so it lands
## while the hit still reads.


func speed() -> float:
	return 1.5


func windup(steps: SequenceSteps) -> void:
	steps.on_user("psychic_actor", "root")
	steps.on_user("psychic_actordots", "root")


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("psychic_target", "root")
	steps.on_foe("psychic_impact", "target", {"delay": 0.2, "scale": 1.4})
	steps.on_foe("psychic_impactdots", "target", {"delay": 0.2})
