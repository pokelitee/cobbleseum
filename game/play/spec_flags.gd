class_name SpecFlags
extends RefCounted
## Battle specs from command-line flags, so a battle can be started without a spec file
## (concepts_brief.md §10). Shared by the battle view and tools/record.gd.
## - --play=<species>: the player against --vs, which --ai controls.
## - --watch=<species>: AI against AI; --ai controls it and --vs-ai (default: --ai) its foe.
## --vs defaults to DEFAULT_FOE and --seed to one from the clock; --arena picks the arena.

const DEFAULT_FOE := "blastoise"
const KEYS: Array[String] = ["play", "watch", "vs", "ai", "vs-ai", "seed", "arena"]


## Splits `args` into these flags {key: value} and every other argument.
static func parse(args: PackedStringArray) -> Dictionary:
	var flags := {}
	var rest: PackedStringArray = []
	for arg in args:
		var key := arg.trim_prefix("--").get_slice("=", 0)
		if arg.begins_with("--") and arg.contains("=") and key in KEYS:
			flags[key] = arg.get_slice("=", 1)
		else:
			rest.append(arg)
	return {"flags": flags, "rest": rest}


## The spec the flags describe, {} when they name no battle (neither --play nor --watch), or
## {"error": String}.
static func to_spec(flags: Dictionary) -> Dictionary:
	var play: String = flags.get("play", "")
	var watch: String = flags.get("watch", "")
	if play.is_empty() and watch.is_empty():
		return {}
	if not play.is_empty() and not watch.is_empty():
		return {"error": "use --play or --watch, not both"}
	if not play.is_empty() and flags.has("vs-ai"):
		return {"error": "--vs-ai is for --watch; with --play, --ai sets the foe's AI"}
	var seed := str(flags.get("seed", ""))
	var ai: String = flags.get("ai", Controllers.DEFAULT_AI)
	var foe: String = flags.get("vs", DEFAULT_FOE)
	var spec := {"seed": seed.to_int() if seed.is_valid_int() else int(Time.get_ticks_usec() % 1000000), "fighters": [
		{"species": play if watch.is_empty() else watch, "ai": "player" if watch.is_empty() else ai},
		{"species": foe, "ai": ai if watch.is_empty() else flags.get("vs-ai", ai)},
	]}
	if flags.has("arena"):
		spec.arena = flags.arena
	return spec


## Flags that describe `spec` exactly (seed included), for passing a battle on to another process.
static func from_spec(spec: Dictionary) -> PackedStringArray:
	var fighters: Array = spec.fighters
	var playing: bool = fighters[0].ai == "player"
	return PackedStringArray([
		"--%s=%s" % ["play" if playing else "watch", fighters[0].species],
		"--vs=%s" % fighters[1].species,
		"--ai=%s" % (fighters[1].ai if playing else fighters[0].ai),
	] + ([] if playing else ["--vs-ai=%s" % fighters[1].ai]) + ["--seed=%d" % int(spec.seed)]
		+ (["--arena=%s" % spec.arena] if spec.has("arena") else []))
