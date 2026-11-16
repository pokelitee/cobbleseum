class_name ArenaSound
extends Node
## The arena's ambience (concepts_brief.md §12.7), on the Crowd bus, from CC0 recordings the
## asset pipeline fetches (sources.json):
## - in a coliseum, the crowd: a murmur as loud as the stands are full, cheers that swell and
##   fade with the crowd's excitement (Crowd.excitement), and a roar at a knockout and the victory;
## - in the open, the field's own sound: wind and birds, surf, rumble, drips.
## It runs in real time: hit-stop and slow motion don't freeze it. Missing files are skipped.

const SOURCES_DIR := "res://cache/sources"
const BUS := &"Crowd"
## Each recording: its source in sources.json, its file, and a trim (dB) that evens out how
## loud the recordings are, so a full crowd and every field sit at about the same level.
const MURMUR := {"source": "crowd_murmur", "file": "crowd_murmur.mp3", "db": -16.0}
const CHEERS: Array[Dictionary] = [
	{"source": "crowd_cheer_1", "file": "crowd_cheer_1.mp3", "db": -12.0},
	{"source": "crowd_cheer_2", "file": "crowd_cheer_2.mp3", "db": -8.5},
	{"source": "crowd_cheer_3", "file": "crowd_cheer_3.mp3", "db": 5.0},
]
const ROAR := {"source": "crowd_roar", "file": "crowd_roar.mp3", "db": -11.0}
const FIELDS := {
	"grassland": {"source": "ambience_grassland", "file": "grassland.ogg", "db": 1.5},
	"beach": {"source": "ambience_beach", "file": "beach.mp3", "db": -3.5},
	"volcano": {"source": "ambience_volcano", "file": "volcano.mp3", "db": -0.5},
	"snowfield": {"source": "ambience_snowfield", "file": "snowfield.ogg", "db": -2.0},
	"cave": {"source": "ambience_cave", "file": "cave.ogg", "db": -2.5},
}
## How far the crowd dips while the victory sting plays, and how quickly.
const STING_DUCK_DB := -6.0
const DUCK_FRAMES := 15
## Excitement below this lets a cheer end, so the next one starts fresh.
const QUIET := 0.05
const SILENT_DB := -60.0

var _root := SOURCES_DIR
var _enclosed := false
var _bed: AudioStreamPlayer
var _cheer: AudioStreamPlayer
var _cheer_db := 0.0
var _cheers_played := 0
var _roar: AudioStreamPlayer
## An offset (dB) on everything this plays, moved by set_level() over a few frames.
var level_db := 0.0
var _level_fade := {}


## The bed for an arena: the crowd's murmur in a coliseum with `fill` of its seats taken,
## else the field's ambience (none for a field without one).
func setup(enclosed: bool, field: String, fill: float, root := SOURCES_DIR) -> void:
	_root = root
	_enclosed = enclosed
	var bed := bed_for(enclosed, field, fill)
	if bed.is_empty():
		return
	_bed = _player(bed, true)


## The bed's recording and volume (dB) for an arena, or {} for none: the murmur in a coliseum,
## quieter the emptier its stands, else the field's ambience.
static func bed_for(enclosed: bool, field: String, fill: float) -> Dictionary:
	if enclosed:
		if fill <= 0.0:
			return {}
		var bed := MURMUR.duplicate()
		bed.db = float(bed.db) + linear_to_db(fill)
		return bed
	return FIELDS.get(field, {}).duplicate()


## A cheer's volume (dB) at an excitement from 0 to 1.
static func cheer_volume(trim_db: float, excitement: float) -> float:
	return trim_db + linear_to_db(clampf(excitement, 0.001, 1.0))


func start() -> void:
	if _bed != null:
		_bed.play()


## Starts a cheer when the crowd isn't already cheering; its volume then follows the crowd.
func cheer() -> void:
	if not _enclosed or (_cheer != null and _cheer.playing):
		return
	var pick: Dictionary = CHEERS[_cheers_played % CHEERS.size()]
	_cheers_played += 1
	if _cheer != null:
		_cheer.queue_free()
	_cheer = _player(pick, false)
	if _cheer != null:
		_cheer_db = pick.db
		_cheer.volume_db = SILENT_DB
		_cheer.play()


## The crowd roars, at a knockout or the victory, unless it is roaring already.
func roar() -> void:
	if not _enclosed or (_roar != null and _roar.playing):
		return
	if _roar == null:
		_roar = _player(ROAR, false)
	if _roar != null:
		_roar.play()


## Moves the level of everything this plays to `db` over `frames`: down under the victory
## sting, to silence over the credits.
func set_level(db: float, frames: int) -> void:
	_level_fade = {"from": level_db, "to": db, "frames": maxi(frames, 1), "done": 0}


## Follows the crowd's excitement (0 to 1) this frame.
func next_frame(excitement: float) -> void:
	if not _level_fade.is_empty():
		_level_fade.done += 1
		level_db = BattleMusic.fade_db(_level_fade.from, _level_fade.to, float(_level_fade.done) / _level_fade.frames)
		if _level_fade.done >= _level_fade.frames:
			_level_fade = {}
	for player: AudioStreamPlayer in [_bed, _roar]:
		if player != null:
			player.volume_db = maxf(player.get_meta("db") + level_db, SILENT_DB)
	if _cheer == null or not _cheer.playing:
		return
	if excitement < QUIET:
		_cheer.stop()
		return
	_cheer.volume_db = maxf(cheer_volume(_cheer_db, excitement) + level_db, SILENT_DB)


func _player(sound: Dictionary, loop: bool) -> AudioStreamPlayer:
	var path := _root.path_join(sound.source).path_join("1").path_join(sound.file)
	if not FileAccess.file_exists(path):
		return null
	var stream: AudioStream
	if path.get_extension() == "mp3":
		stream = AudioStreamMP3.load_from_file(path)
	else:
		stream = AudioStreamOggVorbis.load_from_file(path)
	if stream == null:
		push_error("cannot load sound %s" % path)
		return null
	stream.loop = loop
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = BUS
	player.volume_db = float(sound.db) + level_db
	player.set_meta("db", float(sound.db))
	add_child(player)
	return player
