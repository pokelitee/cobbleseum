class_name AssetPipeline
extends RefCounted
## Fetches, verifies, extracts, checks and builds the pinned asset sources in sources.json.
## See concepts_brief.md §6. Each step writes a stamp and is skipped when its inputs are unchanged.
## Steps return an error message, or "" on success.

## Bump when extraction or stamping changes in a way that invalidates existing caches.
const TOOL_VERSION := "1"
const STAMP_FILE := ".stamp"
const INDEX_FILE := ".files"
const REQUIRED_FIELDS: Array[String] = ["version", "url", "size", "sha256", "archive", "license", "extract", "layout"]
const ARCHIVE_TYPES: Array[String] = ["zip", "tgz"]
const RENAME_ATTEMPTS := 20
const RENAME_RETRY_MS := 500

var cache_dir: String
var offline: bool


func _init(cache_path: String, offline_mode := false) -> void:
	cache_dir = cache_path
	offline = offline_mode


## Returns {"sources": Dictionary} or {"error": String}.
static func load_manifest(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"error": "manifest %s not found" % path}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or not data.get("sources") is Dictionary:
		return {"error": "%s must be a JSON object with a \"sources\" object" % path}
	for id: String in data.sources:
		var problem := validate_source(id, data.sources[id])
		if not problem.is_empty():
			return {"error": "%s: %s" % [path, problem]}
	return {"sources": data.sources}


static func validate_source(id: String, source: Variant) -> String:
	if not source is Dictionary:
		return "source '%s' must be an object" % id
	for field in REQUIRED_FIELDS:
		if not source.has(field):
			return "source '%s' is missing \"%s\"" % [id, field]
	if not source.archive in ARCHIVE_TYPES:
		return "source '%s' has unknown archive type '%s'" % [id, source.archive]
	if not (source.sha256 is String and source.sha256.length() == 64 and source.sha256.is_valid_hex_number()):
		return "source '%s' needs a 64-character hex \"sha256\"" % id
	if not source.extract is Array or source.extract.is_empty():
		return "source '%s' needs a non-empty \"extract\" list" % id
	if not source.layout is Array or source.layout.is_empty():
		return "source '%s' needs a non-empty \"layout\" list" % id
	for rule: Variant in source.layout:
		if not (rule is Dictionary and rule.get("pattern") is String and rule.has("min_count")):
			return "source '%s' has a layout rule without \"pattern\" and \"min_count\"" % id
	return ""


## Creates the cache folder with a .gdignore so the Godot editor never imports its contents.
func prepare_cache() -> String:
	var err := DirAccess.make_dir_recursive_absolute(cache_dir)
	if err != OK:
		return "cannot create cache folder %s (%s)" % [cache_dir, error_string(err)]
	var marker := cache_dir.path_join(".gdignore")
	if not FileAccess.file_exists(marker):
		FileAccess.open(marker, FileAccess.WRITE).close()
	return ""


func archive_path(source: Dictionary) -> String:
	return cache_dir.path_join("downloads").path_join("%s.%s" % [source.sha256, source.archive])


func source_dir(id: String, source: Dictionary) -> String:
	return cache_dir.path_join("sources").path_join(id).path_join(source.version)


func build_dir(id: String, source: Dictionary) -> String:
	return cache_dir.path_join("build").path_join(id).path_join(source.version)


## Downloads the archive unless a verified copy is already cached. A coroutine: await it.
func fetch(id: String, source: Dictionary, tree: SceneTree) -> String:
	var path := archive_path(source)
	if FileAccess.file_exists(path) and FileAccess.get_sha256(path) == source.sha256:
		print("%s %s: archive already cached" % [id, source.version])
		return ""
	if offline:
		return "%s %s is not in the cache and --offline was given. Run once without --offline to download it." % [id, source.version]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var part := path + ".part"
	print("%s %s: downloading %s (%s)" % [id, source.version, source.url, String.humanize_size(int(source.size))])
	var request := HTTPRequest.new()
	request.download_file = part
	request.use_threads = true
	tree.root.add_child(request)
	var err := request.request(source.url, PackedStringArray(["User-Agent: cobbleseum-asset-pipeline"]))
	if err != OK:
		request.queue_free()
		return "%s: cannot start download (%s)" % [id, error_string(err)]
	var response: Array = await request.request_completed
	request.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200:
		DirAccess.remove_absolute(part)
		return "%s: download of %s failed (result %d, HTTP %d)" % [id, source.url, response[0], response[1]]
	return store_download(id, source, part)


## Verifies a downloaded file's size and SHA-256, then moves it into downloads/.
## A file that fails verification is deleted, never used.
func store_download(id: String, source: Dictionary, downloaded: String) -> String:
	var size := _file_size(downloaded)
	if size != int(source.size):
		DirAccess.remove_absolute(downloaded)
		return "%s %s: downloaded %d bytes, expected %d; the file was discarded" % [id, source.version, size, int(source.size)]
	var digest := FileAccess.get_sha256(downloaded)
	if digest != source.sha256:
		DirAccess.remove_absolute(downloaded)
		return "%s %s: SHA-256 mismatch (expected %s, got %s); the file was discarded" % [id, source.version, source.sha256, digest]
	var target := archive_path(source)
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	var err := DirAccess.rename_absolute(downloaded, target)
	if err != OK:
		return "%s: cannot move download into the cache (%s)" % [id, error_string(err)]
	return ""


## Extracts the wanted entries and checks them against the layout rules before committing,
## so a cached extraction has always passed the current rules.
func extract(id: String, source: Dictionary) -> String:
	var out := source_dir(id, source)
	var key := _stamp_key([source.sha256, JSON.stringify(source.extract), JSON.stringify(source.layout), TOOL_VERSION])
	if _stamp_matches(out, key):
		print("%s %s: already extracted and checked" % [id, source.version])
		return ""
	print("%s %s: extracting (this can take a few minutes)" % [id, source.version])
	var staging := out + ".tmp"
	_remove_tree(staging)
	var written: Array = []
	var err := ""
	if source.archive == "zip":
		err = ZipReader.extract(archive_path(source), source.extract, staging, written)
	else:
		err = TarReader.extract_tgz(archive_path(source), source.extract, staging, written)
	if err.is_empty():
		err = check_layout(id, source, staging, PackedStringArray(written))
	if not err.is_empty():
		_remove_tree(staging)
		return err if err.begins_with(id) else "%s %s: %s" % [id, source.version, err]
	var index := FileAccess.open(staging.path_join(INDEX_FILE), FileAccess.WRITE)
	index.store_string("\n".join(PackedStringArray(written)))
	index.close()
	return _commit(staging, out, key)


## Confirms every layout rule; on failure explains that the upstream layout may have changed.
static func check_layout(id: String, source: Dictionary, root: String, files: PackedStringArray) -> String:
	var problems: PackedStringArray = []
	for rule: Dictionary in source.layout:
		var pattern: String = rule.pattern
		var matches := Array(files).filter(func(f: String) -> bool: return f.match(pattern))
		if matches.size() < int(rule.min_count):
			problems.append("expected at least %d files matching '%s', found %d" % [int(rule.min_count), pattern, matches.size()])
		elif rule.has("format_key"):
			for file: String in matches:
				var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(root.path_join(file)))
				var found: Variant = data.get(rule.format_key) if data is Dictionary else null
				if found != rule.format_value:
					problems.append("%s has %s %s, expected %s" % [file, rule.format_key, var_to_str(found), var_to_str(rule.format_value)])
					break
	if problems.is_empty():
		return ""
	return ("%s %s: the archive doesn't match the layout in sources.json:\n  - %s\n" +
		"The upstream layout may have changed. Update the pinned version and its layout rules together.") % [
			id, source.version, "\n  - ".join(problems)]


## Runs the source's build script, if it has one, from the extracted files into build/.
func build(id: String, source: Dictionary) -> String:
	if not source.has("build"):
		return ""
	var script_path: String = source.build
	var script: GDScript = load(script_path)
	if script == null:
		return "%s: cannot load build script %s" % [id, script_path]
	var out := build_dir(id, source)
	var key := _stamp_key([source.sha256, FileAccess.get_sha256(script_path), _build_dependencies_hash(script), TOOL_VERSION])
	if _stamp_matches(out, key):
		print("%s %s: build up to date" % [id, source.version])
		return ""
	print("%s %s: building" % [id, source.version])
	var staging := out + ".tmp"
	_remove_tree(staging)
	DirAccess.make_dir_recursive_absolute(staging)
	var err: String = script.new().build(source_dir(id, source), staging)
	if not err.is_empty():
		_remove_tree(staging)
		return "%s %s: %s" % [id, source.version, err]
	return _commit(staging, out, key)


## Relative paths of the files an extraction wrote, read from its index.
## Listing folders instead is far slower: tens of seconds for the Cobblemon subset on Windows.
static func indexed_files(dir: String) -> PackedStringArray:
	var index := dir.path_join(INDEX_FILE)
	if not FileAccess.file_exists(index):
		return PackedStringArray()
	return FileAccess.get_file_as_string(index).split("\n", false)


static func _build_dependencies_hash(script: GDScript) -> String:
	# A build script can list extra files (e.g. a Node helper) whose changes must invalidate the build.
	var parts: PackedStringArray = []
	for path: String in script.get_script_constant_map().get("DEPENDENCIES", []):
		parts.append(FileAccess.get_sha256(path))
	return "|".join(parts)


static func _stamp_key(parts: Array) -> String:
	return "|".join(parts.map(func(p: Variant) -> String: return str(p))).sha256_text()


static func _stamp_matches(dir: String, key: String) -> bool:
	var stamp := dir.path_join(STAMP_FILE)
	return FileAccess.file_exists(stamp) and FileAccess.get_file_as_string(stamp).strip_edges() == key


## Writes the stamp into the staging folder, then swaps it into place so a half-finished
## step never looks complete.
static func _commit(staging: String, out: String, key: String) -> String:
	var stamp := FileAccess.open(staging.path_join(STAMP_FILE), FileAccess.WRITE)
	stamp.store_string(key)
	stamp.close()
	_remove_tree(out)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	# On Windows, antivirus scanning can briefly hold freshly written files open,
	# which makes renaming their folder fail. Retry for a few seconds before giving up.
	var err := OK
	for attempt in RENAME_ATTEMPTS:
		err = DirAccess.rename_absolute(staging, out)
		if err == OK:
			return ""
		OS.delay_msec(RENAME_RETRY_MS)
	return "cannot move %s into place (%s)" % [out, error_string(err)]


static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	# Delete indexed files directly first; the walk below then only meets folders and leftovers.
	for file in indexed_files(path):
		DirAccess.remove_absolute(path.path_join(file))
	# The static get_files_at() skips dotfiles on Linux and macOS, which would leave .stamp
	# and .files behind and keep the folder from being removed.
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


static func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	return -1 if file == null else file.get_length()
