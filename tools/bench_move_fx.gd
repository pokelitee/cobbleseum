extends SceneTree
## Measures what move sequences cost per video frame (concepts_brief.md §12.5), to keep live
## play at frame rate: the target is under 5 ms in the worst frame with two moves overlapping.
## Usage: godot --headless --path . --script res://tools/bench_move_fx.gd -- [move ...]
## With no moves, every move with a sequence is measured, each alone and then alongside the
## next one. Needs the Cobblemon move effects in the cache (tools/assets.gd).

const FRAMES := 90
## When the hit lands, in frames after the windup starts.
const HIT_FRAME := 15
const TARGET_MS := 5.0


func _initialize() -> void:
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
	var moves: Array = Array(OS.get_cmdline_user_args())
	if moves.is_empty():
		for file in DirAccess.get_files_at(MoveSequence.DIR):
			if file.ends_with(".gd"):
				moves.append(file.get_basename())
	fx.prepare(moves)
	var worst_overall := 0.0
	for i in moves.size():
		var alone := _measure(fx, [moves[i]], user, foe)
		var paired := _measure(fx, [moves[i], moves[(i + 1) % moves.size()]], user, foe) if moves.size() > 1 else alone
		worst_overall = maxf(worst_overall, paired.worst)
		print("%-14s alone: worst %5.1f ms, mean %4.2f ms, %3d particles | with %-14s worst %5.1f ms" % [
			moves[i], alone.worst, alone.mean, alone.peak, moves[(i + 1) % moves.size()], paired.worst])
	print("worst frame with two moves: %.1f ms (target %.0f ms)" % [worst_overall, TARGET_MS])
	quit(0)


## Plays every phase of the moves together and times each frame.
func _measure(fx: CobblemonMoveFX, moves: Array, user: FighterView, foe: FighterView) -> Dictionary:
	var riders: Array[Node3D] = []
	for id: String in moves:
		for phase in ["windup", "fire", "blast"]:
			fx.play(id, phase, user, foe, Color.WHITE, HIT_FRAME)
		var rider := Node3D.new()
		root.add_child(rider)
		rider.position = Vector3(-2, 1, 0)
		riders.append(rider)
		fx.play_riding(id, "flight", rider, user, foe, Color.WHITE)
	var worst := 0.0
	var total := 0.0
	var peak := 0
	for frame in FRAMES:
		if frame == HIT_FRAME:
			for id: String in moves:
				fx.play(id, "hit", user, foe, Color.WHITE)
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
