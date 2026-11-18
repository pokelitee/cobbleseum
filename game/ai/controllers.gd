class_name Controllers
extends RefCounted
## Builds each side's controller from a battle spec (concepts_brief.md §10, §11). A fighter's
## "ai" names a profile in game/ai/profiles ("easy", "normal", "hard", "ranked"), "stand_in"
## for the stand-in AI (StandInAI), or "player"; the default is "ranked". A fighter with
## recorded "intents" (a player's side of a saved battle spec) is replayed instead. Each side
## draws from its own random stream of the battle seed, so every run of a spec makes the same
## choices.
##
## Doubles (a spec's "doubles": true) has a controller per fighter out, in Battle.index_of
## order: each side's first runs on its "ai" (or "intents"), its second on the same AI with a
## stream of its own, or on "ally_ai" (default "ranked") when the first is the player, or replays
## "ally_intents".

const PROFILES_DIR := "res://game/ai/profiles"
const DEFAULT_AI := "ranked"


## Returns {"controllers": [side A, side B] (in doubles [A, B, A's second, B's second])} or
## {"error": String}.
static func for_spec(spec: Dictionary) -> Dictionary:
	var controllers := []
	var places := 2 if spec.get("doubles", false) == true else 1
	for index in 2 * places:
		var side := index % 2
		var second := index >= 2
		var entry: Dictionary = spec.get("fighters", [{}, {}])[side] if spec.get("fighters", []).size() == 2 else {}
		var name := str(entry.get("ai", DEFAULT_AI))
		var streams := [[Battle.Stream.SIDE_A, Battle.Stream.SIDE_B], [Battle.Stream.SIDE_A2, Battle.Stream.SIDE_B2]]
		var stream := SimRandom.stream(int(spec.get("seed", 0)), streams[1 if second else 0][side])
		var recorded: Variant = entry.get("ally_intents" if second else "intents")
		if recorded is Array:
			controllers.append(ReplayController.new(recorded))
			continue
		if second and name == "player":
			name = str(entry.get("ally_ai", DEFAULT_AI))
		if name == "player":
			controllers.append(PlayerController.new())
			continue
		if name == "stand_in":
			controllers.append(StandInAI.new(stream))
			continue
		var profile := load_profile(name)
		if profile == null:
			return {"error": "unknown AI '%s' (use stand_in or a profile in %s)" % [name, PROFILES_DIR]}
		controllers.append(UtilityAI.new(profile, stream))
	return {"controllers": controllers}


static func load_profile(name: String) -> AIProfile:
	var path := PROFILES_DIR.path_join(name + ".tres")
	return load(path) as AIProfile if ResourceLoader.exists(path) else null
