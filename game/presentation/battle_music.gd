class_name BattleMusic
extends Node
## Battle music (concepts_brief.md §12.5): one of the original tracks the asset pipeline renders
## (tools/sources/music.gd), played on the Music bus, which ducks under the battle's sounds.
## The battle's seed picks the track and its drum and lead variants, on a random stream of its
## own. The cues follow the battle, in video frames:
## - start(): the track fades in from the top (its intro plays once, then it loops);
## - overtime(): the climax layer fades in;
## - knockout(): the music cuts within CUT_FRAMES, leaving the cry and the crowd;
## - victory(): the sting plays, after `delay` frames;
## - draw(): the music fades out;
## - fade_out(): whatever plays fades away, as the credits do.
## Without rendered music (no cache) it stays silent.

const MUSIC_DIR := "res://cache/build/generaluser_gs/2.0.3"
const BUS := &"Music"
const FADE_IN_FRAMES := 15
const CUT_FRAMES := 9
const DRAW_FRAMES := 60
const CLIMAX_FRAMES := 45
## Volumes at or below this count as silent: a fade that reaches it stops the player.
const SILENT_DB := -60.0
## The variants of a layer the seed chooses between.
const VARIANT_LAYERS: Array[String] = ["drums", "lead"]
const FIXED_LAYERS: Array[String] = ["bass", "harmony"]
const CLIMAX := "climax"

## The chosen track's id, and the variant of each varying layer.
var track := ""
var variants := {}

var _dir := MUSIC_DIR
var _manifest := {}
var _music: AudioStreamPlayer
var _sync: AudioStreamSynchronized
var _climax_index := -1
var _sting: AudioStreamPlayer
var _sting_frame := -1
var _frame := 0
## Fades in progress: {"music" | "climax" | "sting": {"from": dB, "to": dB, "frames": n, "done": n}}.
var _fades := {}


## Reads the rendered music in `dir` and picks the track and variants with `random`.
## Returns false, leaving everything silent, when there is no rendered music.
func setup(random: SimRandom, dir := MUSIC_DIR) -> bool:
	_dir = dir
	var path := dir.path_join("music.json")
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary and parsed.get("tracks") is Dictionary and not parsed.tracks.is_empty()):
		push_error("%s is not a music manifest; run tools/assets.gd again" % path)
		return false
	_manifest = parsed
	var choice := choose(_manifest.tracks, random)
	track = choice.track
	variants = choice.variants
	return _build_stream()


## The track and variants for a battle: picked by `random`, from the tracks sorted by id so the
## same seed always gets the same music.
static func choose(tracks: Dictionary, random: SimRandom) -> Dictionary:
	var ids := tracks.keys()
	ids.sort()
	var id: String = ids[random.next_u32() % ids.size()]
	var picked := {}
	for layer in VARIANT_LAYERS:
		var count := 0
		while tracks[id].layers.has("%s_%d" % [layer, count]):
			count += 1
		picked[layer] = random.next_u32() % maxi(count, 1)
	return {"track": id, "variants": picked}


func start() -> void:
	if _music == null:
		return
	_music.volume_db = SILENT_DB
	_music.play()
	_fade("music", 0.0, FADE_IN_FRAMES)


func overtime() -> void:
	if _music != null and _climax_index >= 0:
		_fade("climax", 0.0, CLIMAX_FRAMES)


func knockout() -> void:
	if _music != null and _music.playing:
		_fade("music", SILENT_DB, CUT_FRAMES)


func draw() -> void:
	if _music != null and _music.playing:
		_fade("music", SILENT_DB, DRAW_FRAMES)


func victory(delay := 0) -> void:
	if _manifest.is_empty() or _sting_frame >= 0:
		return
	_sting_frame = _frame + delay


## Fades out the music and the sting, if either is playing; a sting still waiting won't start.
func fade_out(frames: int) -> void:
	if _music != null and _music.playing:
		_fade("music", SILENT_DB, frames)
	if _sting != null:
		_fade("sting", SILENT_DB, frames)
	elif _sting_frame > _frame:
		_sting_frame = -1


## The music's volume (dB) now, SILENT_DB without music.
func music_db() -> float:
	return _music.volume_db if _music != null else SILENT_DB


func climax_db() -> float:
	return _sync.get_sync_stream_volume(_climax_index) if _climax_index >= 0 else SILENT_DB


func sting_started() -> bool:
	return _sting != null


func next_frame() -> void:
	if _sting_frame >= 0 and _frame == _sting_frame:
		_play_sting()
	for key: String in _fades.keys():
		var fade: Dictionary = _fades[key]
		fade.done += 1
		var db := fade_db(fade.from, fade.to, float(fade.done) / fade.frames)
		_set_db(key, db)
		if fade.done >= fade.frames:
			_fades.erase(key)
			if db <= SILENT_DB:
				_stop(key)
	_frame += 1


## The volume (dB) a fade from `from` to `to` has reached at `progress` (0 to 1). It moves in
## amplitude, not in dB, so it sounds even: a fade in dB spends half its time almost silent.
static func fade_db(from: float, to: float, progress: float) -> float:
	if progress >= 1.0:
		return to
	var amplitude := lerpf(db_to_linear(from), db_to_linear(to), clampf(progress, 0.0, 1.0))
	return maxf(linear_to_db(maxf(amplitude, 1e-6)), SILENT_DB)


func _build_stream() -> bool:
	var layers: Dictionary = _manifest.tracks[track].layers
	var names: Array[String] = []
	for layer in VARIANT_LAYERS:
		names.append("%s_%d" % [layer, variants[layer]])
	names.append_array(FIXED_LAYERS)
	if layers.has(CLIMAX):
		names.append(CLIMAX)
	_sync = AudioStreamSynchronized.new()
	_sync.stream_count = names.size()
	for i in names.size():
		var stream := _load_layer(layers.get(names[i], ""))
		if stream == null:
			return false
		_sync.set_sync_stream(i, stream)
		if names[i] == CLIMAX:
			_climax_index = i
			_sync.set_sync_stream_volume(i, SILENT_DB)
	_music = AudioStreamPlayer.new()
	_music.stream = _sync
	_music.bus = BUS
	add_child(_music)
	return true


func _load_layer(file: String) -> AudioStreamWAV:
	var path := _dir.path_join(file)
	var stream := AudioStreamWAV.load_from_file(path) if not file.is_empty() and FileAccess.file_exists(path) else null
	if stream == null:
		push_error("cannot load music layer %s; run tools/assets.gd again" % path)
		return null
	var info: Dictionary = _manifest.tracks[track]
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = int(info.loop_begin)
	stream.loop_end = int(info.loop_end)
	return stream


func _play_sting() -> void:
	var path := _dir.path_join(str(_manifest.get("sting", "")))
	var stream := AudioStreamWAV.load_from_file(path) if FileAccess.file_exists(path) else null
	if stream == null:
		push_error("cannot load the victory sting %s; run tools/assets.gd again" % path)
		return
	_sting = AudioStreamPlayer.new()
	_sting.stream = stream
	_sting.bus = BUS
	add_child(_sting)
	_sting.play()


func _fade(key: String, to: float, frames: int) -> void:
	_fades[key] = {"from": _db(key), "to": to, "frames": maxi(frames, 1), "done": 0}


func _db(key: String) -> float:
	match key:
		"music":
			return _music.volume_db
		"climax":
			return _sync.get_sync_stream_volume(_climax_index)
		_:
			return _sting.volume_db if _sting != null else SILENT_DB


func _set_db(key: String, db: float) -> void:
	match key:
		"music":
			_music.volume_db = db
		"climax":
			_sync.set_sync_stream_volume(_climax_index, db)
		_:
			if _sting != null:
				_sting.volume_db = db


func _stop(key: String) -> void:
	if key == "music":
		_music.stop()
	elif key == "sting" and _sting != null:
		_sting.stop()
