class_name BattleSound
extends Node
## Battle sound (concepts_brief.md §12.5) from Cobblemon's sound files:
## - cries: both fighters at the intro, and a lower-pitched cry on a faint
## - wind-up: the move's own `<move>_actor*` sound, when Cobblemon has one
## - hits: the move's `<move>_target*` sound, else the generic impact sound for its type
## Variants are chosen by a counter, never at random, so every render sounds the same.
## Sounds start on video frames; missing files are skipped silently, since most moves and
## some species have no sound of their own.

const SOUNDS_DIR := "res://cache/sources/cobblemon/1.8.4/assets/cobblemon/sounds"
## Frames between the two intro cries, so they don't play over each other.
const INTRO_CRY_GAP := 24
const FAINT_PITCH := 0.8
const CRY_DB := -7.0
const MOVE_DB := -6.0
const BIG_HIT_DB := 2.0
const MISS_DB := -8.0

var _root := SOUNDS_DIR
var _species: Array[String] = ["", ""]
var _streams := {}
var _listings := {}
var _played := {}
## Sounds waiting for their frame: {"frame": int, "path": String, "db": float, "pitch": float}.
var _queue: Array[Dictionary] = []
var _frame := 0


func setup(species: Array, root := SOUNDS_DIR) -> void:
	_root = root
	for side in 2:
		_species[side] = str(species[side])


func intro() -> void:
	_schedule(0, cry_path(0), CRY_DB)
	_schedule(INTRO_CRY_GAP, cry_path(1), CRY_DB)


func faint(side: int) -> void:
	_schedule(0, cry_path(side), CRY_DB, FAINT_PITCH)


func windup(move: BattleMove) -> void:
	_schedule(0, move_path(move.id, "actor"), MOVE_DB)


func hit(move: BattleMove, big: bool) -> void:
	var path := move_path(move.id, "target")
	if path.is_empty():
		path = impact_path(move.type)
	_schedule(0, path, MOVE_DB + (BIG_HIT_DB if big else 0.0))


func miss(move: BattleMove) -> void:
	_schedule(0, impact_path(move.type), MISS_DB, 1.3)


func cry_path(side: int) -> String:
	var path := _root.path_join("pokemon/%s/%s_cry.ogg" % [_species[side], _species[side]])
	return path if FileAccess.file_exists(path) else ""


## The next variant of the move's actor or target sound, or "" if Cobblemon has none.
func move_path(move_id: String, role: String) -> String:
	return _next_variant("move/" + move_id, "%s_%s" % [move_id, role])


## The next variant of the generic impact sound for a type, or "" if there is none.
func impact_path(type: String) -> String:
	return _next_variant("move/impact_generic", "impact_generic_%s_" % type.to_lower())


## Starts any sounds due on this video frame.
func next_frame() -> void:
	for sound in _queue.duplicate():
		if sound.frame <= _frame:
			_play(sound)
			_queue.erase(sound)
	_frame += 1


func _schedule(delay_frames: int, path: String, db: float, pitch := 1.0) -> void:
	if not path.is_empty():
		_queue.append({"frame": _frame + delay_frames, "path": path, "db": db, "pitch": pitch})


func _play(sound: Dictionary) -> void:
	var stream := _stream(sound.path)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = sound.db
	player.pitch_scale = sound.pitch
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


func _stream(path: String) -> AudioStream:
	if not _streams.has(path):
		_streams[path] = AudioStreamOggVorbis.load_from_file(path)
		if _streams[path] == null:
			push_error("cannot load sound %s" % path)
	return _streams[path]


func _next_variant(folder: String, prefix: String) -> String:
	var key := folder.path_join(prefix)
	if not _listings.has(key):
		var dir := _root.path_join(folder)
		var names := DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray()
		var files := Array(names).filter(func(f: String) -> bool:
			return f.begins_with(prefix) and f.ends_with(".ogg"))
		files.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
		_listings[key] = files.map(func(f: String) -> String: return dir.path_join(f))
	var variants: Array = _listings[key]
	if variants.is_empty():
		return ""
	var count: int = _played.get(key, 0)
	_played[key] = count + 1
	return variants[count % variants.size()]
