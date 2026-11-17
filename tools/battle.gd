extends SceneTree
## Headless battle runner (concepts_brief.md §10).
## Usage: godot --headless --path . --script res://tools/battle.gd -- <spec.json> [--seeds=N]
## Runs the spec (or N consecutive seeds starting at its seed), prints the resolved battle, one
## JSON line per battle with the result, length, arena and checksum, then the average time per
## battle. Battle flags (SpecFlags: --watch=<species> --vs=... --seed=...) can stand in for the
## spec file; --help lists them.

const HELP := """Runs battles headless and prints each one's result, length and checksum.

Usage: godot --headless --path . --script res://tools/battle.gd -- <spec.json> [--seeds=N]
       godot --headless --path . --script res://tools/battle.gd -- --watch=<species> [battle flags] [--seeds=N]

  <spec.json>              a battle spec (game/data/battles/showcase.json is one)
  --seeds=N                runs N battles, from the spec's seed onwards (default 1)

%s

%s"""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var handled := Cli.info(args, HELP % [Cli.SPEC_FLAGS_HELP, Cli.INFO_HELP])
	if handled >= 0:
		return quit(handled)
	var parsed := SpecFlags.parse(args)
	var problem := Cli.unknown_option(parsed.rest, ["seeds"])
	if not problem.is_empty():
		return _fail(problem)
	var flag_spec := SpecFlags.to_spec(parsed.flags)
	if flag_spec.has("error"):
		return _fail(flag_spec.error)
	if not flag_spec.is_empty() and flag_spec.fighters[0].ai == "player":
		return _fail("--play needs a player; use --watch here")
	var spec_path := ""
	var seeds := 1
	for arg: String in parsed.rest:
		if arg.begins_with("--seeds="):
			seeds = maxi(1, arg.trim_prefix("--seeds=").to_int())
		else:
			spec_path = arg
	if spec_path.is_empty() and flag_spec.is_empty():
		return _fail("usage: -- <spec.json> | --watch=<species> [battle flags] [--seeds=N] (see --help)")
	var spec: Variant = flag_spec if not flag_spec.is_empty() else JSON.parse_string(FileAccess.get_file_as_string(spec_path))
	if not spec is Dictionary:
		return _fail("cannot read battle spec %s" % spec_path)
	var loaded := BattleData.load_all()
	if loaded.has("error"):
		return _fail(loaded.error)
	problem = Cli.check_spec(spec, loaded.data)
	if not problem.is_empty():
		return _fail(problem)
	if not flag_spec.is_empty():
		Appearance.roll_missing(spec, loaded.data.roster)

	var started := Time.get_ticks_usec()
	for i in seeds:
		var run_spec: Dictionary = spec.duplicate(true)
		run_spec.seed = int(spec.seed) + i
		var summary := run(run_spec, loaded.data, i == 0, not flag_spec.is_empty())
		if summary.has("error"):
			return _fail(summary.error)
		print(JSON.stringify(summary))
	var per_battle_ms := (Time.get_ticks_usec() - started) / 1000.0 / seeds
	print("%d battle(s), %.1f ms per battle" % [seeds, per_battle_ms])
	quit(0)


## Runs `spec` to the end. With `describe`, first prints the resolved battle (Cli.describe), with
## the flags that repeat it when it came `from_flags`.
static func run(spec: Dictionary, data: BattleData, describe := false, from_flags := false) -> Dictionary:
	var controllers := Controllers.for_spec(spec)
	if controllers.has("error"):
		return controllers
	var created := Battle.create(spec, data, controllers.controllers)
	if created.has("error"):
		return created
	var battle: Battle = created.battle
	if describe:
		print("\n".join(Cli.describe(spec, battle, from_flags)))
	var ticks := battle.run()
	return {
		"seed": spec.seed,
		"result": Battle.Result.keys()[battle.result],
		"seconds": snappedf(float(ticks) / Rules.TICK_RATE, 0.01),
		"arena": battle.arena,
		"hp": [battle.fighters[0].hp, battle.fighters[1].hp],
		"hits": battle.events.filter(func(e: Dictionary) -> bool: return e.type == "hit").size(),
		"checksum": battle.checksum(),
	}


func _fail(message: String) -> void:
	printerr("error: " + message)
	quit(1)
