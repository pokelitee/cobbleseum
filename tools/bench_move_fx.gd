extends SceneTree
## Measures what move sequences cost per video frame (concepts_brief.md §12.5), to keep live
## play at frame rate: the target is under 5 ms in the worst frame with two moves overlapping.
## Usage: godot --headless --path . --script res://tools/bench_move_fx.gd -- [move ...]
## With no moves, every move with its own sequence is measured, plus one move per style, each
## alone and then alongside the next one. Needs the Showdown data and the Cobblemon move
## effects in the cache (tools/assets.gd) and the native runtime (tools/native/build.sh).

const FRAMES := 90
## When the hit lands, in frames after the windup starts.
const HIT_FRAME := 15
const TARGET_MS := 5.0


func _initialize() -> void:
	var loaded := BattleData.load_all()
	if loaded.has("error"):
		printerr("error: " + loaded.error)
		quit(1)
		return
	var data: BattleData = loaded.data
	var user := FighterView.new()
	user.height = 1.6
	user.position = Vector3(-3, 0, 0)
	var foe := FighterView.new()
	foe.height = 1.0
	foe.position = Vector3(3, 0, 0)
	root.add_child(user)
	root.add_child(foe)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.look_at_from_position(Vector3(0, 2.2, 8.5), Vector3(0, 1, 0))
	var fx := CobblemonMoveFX.new()
	root.add_child(fx)
	var problem := fx.setup()
	if not problem.is_empty():
		printerr("error: " + problem)
		quit(1)
		return
	var ids: Array = Array(OS.get_cmdline_user_args())
	if ids.is_empty():
		ids = _default_moves(data)
	var moves: Array = []
	for id: String in ids:
		var converted := data.convert_move(id)
		if converted.has("error"):
			printerr("error: " + str(converted.error))
			quit(1)
			return
		var move: BattleMove = converted.move
		moves.append([move, MoveStyle.of(id, data.moves[id]) if move.is_damaging() else "status"])
	fx.prepare(moves)
	var worst_overall := 0.0
	for i in moves.size():
		var next: Array = moves[(i + 1) % moves.size()]
		var alone := _measure(fx, [moves[i]], user, foe)
		var paired := _measure(fx, [moves[i], next], user, foe) if moves.size() > 1 else alone
		worst_overall = maxf(worst_overall, paired.worst)
		print("%-14s %-9s alone: worst %5.1f ms, mean %4.2f ms, %3d particles | with %-14s worst %5.1f ms" % [
			moves[i][0].id, moves[i][1], alone.worst, alone.mean, alone.peak, next[0].id, paired.worst])
	print("worst frame with two moves: %.1f ms (target %.0f ms)" % [worst_overall, TARGET_MS])
	quit(0)


## Every move with its own sequence, then the first damaging move of each style.
func _default_moves(data: BattleData) -> Array:
	var ids: Array = []
	for file in DirAccess.get_files_at(MoveSequence.DIR):
		if file.ends_with(".gd"):
			ids.append(file.get_basename())
	var styles := {}
	for id: String in data.moves:
		var converted := data.convert_move(id)
		if converted.has("error") or not (converted.move as BattleMove).is_damaging():
			continue
		var style := MoveStyle.of(id, data.moves[id])
		if not styles.has(style):
			styles[style] = id
	ids.append_array(styles.values())
	return ids


## Plays every phase of the moves together and times each frame.
func _measure(fx: CobblemonMoveFX, moves: Array, user: FighterView, foe: FighterView) -> Dictionary:
	var riders: Array[Node3D] = []
	for entry: Array in moves:
		for phase in ["windup", "fire", "blast"]:
			fx.play(entry[0], entry[1], phase, user, foe, HIT_FRAME)
		var rider := Node3D.new()
		root.add_child(rider)
		rider.position = Vector3(-2, 1, 0)
		riders.append(rider)
		fx.play_riding(entry[0], entry[1], "flight", rider, user, foe)
	var worst := 0.0
	var total := 0.0
	var peak := 0
	for frame in FRAMES:
		if frame == HIT_FRAME:
			for entry: Array in moves:
				fx.play(entry[0], entry[1], "hit", user, foe)
			for rider in riders:
				rider.queue_free()
		for rider in riders:
			if is_instance_valid(rider):
				rider.position.x += 0.3
		var started := Time.get_ticks_usec()
		fx.next_frame()
		var spent := (Time.get_ticks_usec() - started) / 1000.0
		worst = maxf(worst, spent)
		total += spent
		var count := 0
		for child in fx.get_children():
			if child is SnowstormEmitter:
				count += (child as SnowstormEmitter).particle_count()
		peak = maxi(peak, count)
	fx.end_all()
	for frame in 200:
		fx.next_frame()
	return {"worst": worst, "mean": total / FRAMES, "peak": peak}
