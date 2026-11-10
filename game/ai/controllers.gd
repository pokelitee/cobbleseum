class_name Controllers
extends RefCounted
## Builds each side's controller from a battle spec (concepts_brief.md §10, §11). A fighter's
## "ai" names a profile in game/ai/profiles ("easy", "normal", "hard", "ranked"), "simple"
## for the stand-in SimpleAI, or "player"; the default is "ranked". A fighter with recorded
## "intents" (a replay) is played back instead. Each side draws from its own random
## stream of the battle seed, so every run of a spec makes the same choices.

const PROFILES_DIR := "res://game/ai/profiles"
const DEFAULT_AI := "ranked"


## Returns {"controllers": [side A, side B]} or {"error": String}.
static func for_spec(spec: Dictionary) -> Dictionary:
	var controllers := []
	for side in 2:
		var entry: Dictionary = spec.get("fighters", [{}, {}])[side] if spec.get("fighters", []).size() == 2 else {}
		var name := str(entry.get("ai", DEFAULT_AI))
		var stream := SimRandom.stream(int(spec.get("seed", 0)), Battle.Stream.SIDE_A if side == 0 else Battle.Stream.SIDE_B)
		if entry.get("intents") is Array:
			controllers.append(ReplayController.new(entry.intents))
			continue
		if name == "player":
			controllers.append(PlayerController.new())
			continue
		if name == "simple":
			controllers.append(SimpleAI.new(stream))
			continue
		var profile := load_profile(name)
		if profile == null:
			return {"error": "unknown AI '%s' (use simple or a profile in %s)" % [name, PROFILES_DIR]}
		controllers.append(UtilityAI.new(profile, stream))
	return {"controllers": controllers}


static func load_profile(name: String) -> AIProfile:
	var path := PROFILES_DIR.path_join(name + ".tres")
	return load(path) as AIProfile if ResourceLoader.exists(path) else null
