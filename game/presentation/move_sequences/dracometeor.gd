extends "res://game/presentation/move_sequences/styles/skyfall.gd"
## Draco Meteor: a pulse at the mouth, then meteors falling onto the foe and bursting in
## craters. Each meteor falls from high above the foe for half a second, so the first two
## start as the move is released and the third on the hit. Cobblemon's fourth is left out:
## each meteor's burst is heavy, and four of them pushed a frame near the 5 ms budget. Cobblemon aims them at the foe's
## own feet; ours fall straight onto it, since aiming points at the other fighter.


func speed() -> float:
	return 1.5


func windup(steps: SequenceSteps) -> void:
	steps.on_user("dracometeor_actorpulse", "mouth")
	steps.on_user("dracometeor_accent", "middle", {"delay": 0.2})


func fire(steps: SequenceSteps) -> void:
	steps.on_foe("dracometeor_meteor1")
	steps.on_foe("dracometeor_meteortrail1", "target", {"delay": 0.03})
	steps.on_foe("dracometeor_meteor2", "target", {"delay": 0.15})
	steps.on_foe("dracometeor_meteortrail2", "target", {"delay": 0.18})


func flight(_steps: SequenceSteps) -> void:
	pass


func hit(steps: SequenceSteps) -> void:
	steps.impact()
	steps.on_foe("dracometeor_targetfloorscorch")
	steps.on_foe("dracometeor_meteor3")
	steps.on_foe("dracometeor_meteortrail3", "target", {"delay": 0.03})
