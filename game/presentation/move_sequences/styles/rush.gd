extends StyleSequence
## rush: dash lines and dust as the user charges, then a burst on the foe.


func windup(steps: SequenceSteps) -> void:
	steps.on_user("quickattack_dashlines", "middle", TINT)
	steps.on_user("quickattack_dust", "root")


func hit(steps: SequenceSteps) -> void:
	super(steps)
	steps.on_user("closecombat_actor", "middle", TINT)
	steps.on_foe("tackle_targetsparks", "target", ACCENT)
