extends StyleSequence
## wind: a gust swirling from the user over the foe.


func speed() -> float:
	return 1.4


func fire(steps: SequenceSteps) -> void:
	steps.on_user("icywind_actor", "special", tinted({"aim": true}))
	steps.on_user("gust_actor", "special", tinted({"aim": true}))


func hit(steps: SequenceSteps) -> void:
	super(steps)
	steps.on_foe("gust_targethit", "target", TINT)
