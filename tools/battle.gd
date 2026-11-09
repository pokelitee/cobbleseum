extends SceneTree
## Headless battle runner (concepts_brief.md §10).
## Usage: godot --headless --path . --script res://tools/battle.gd -- <spec.json> [--seeds=N]
## Runs the spec (or N consecutive seeds starting at its seed), prints one JSON line per
## battle with the result, length and checksum, then the average time per battle.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var spec_path := ""
	var seeds := 1
	for arg in args:
		if arg.begins_with("--seeds="):
			seeds = maxi(1, arg.trim_prefix("--seeds=").to_int())
		else:
			spec_path = arg
	if spec_path.is_empty():
		return _fail("usage: -- <spec.json> [--seeds=N]")
	var spec: Variant = JSON.parse_string(FileAccess.get_file_as_string(spec_path))
	if not spec is Dictionary:
		return _fail("cannot read battle spec %s" % spec_path)
	var loaded := BattleData.load_showdown()
	if loaded.has("error"):
		return _fail(loaded.error)

	var started := Time.get_ticks_usec()
	for i in seeds:
		var run_spec: Dictionary = spec.duplicate(true)
		run_spec.seed = int(spec.seed) + i
		var summary := run(run_spec, loaded.data)
		if summary.has("error"):
			return _fail(summary.error)
		print(JSON.stringify(summary))
	var per_battle_ms := (Time.get_ticks_usec() - started) / 1000.0 / seeds
	print("%d battle(s), %.1f ms per battle" % [seeds, per_battle_ms])
	quit(0)


static func run(spec: Dictionary, data: BattleData) -> Dictionary:
	var created := Battle.create(spec, data, SimpleAI.pair(int(spec.seed)))
	if created.has("error"):
		return created
	var battle: Battle = created.battle
	var ticks := battle.run()
	return {
		"seed": spec.seed,
		"result": Battle.Result.keys()[battle.result],
		"seconds": snappedf(float(ticks) / Rules.TICK_RATE, 0.01),
		"hp": [battle.fighters[0].hp, battle.fighters[1].hp],
		"hits": battle.events.filter(func(e: Dictionary) -> bool: return e.type == "hit").size(),
		"checksum": battle.checksum(),
	}


func _fail(message: String) -> void:
	printerr("error: " + message)
	quit(1)
