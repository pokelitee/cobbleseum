class_name ArchiveFiles
extends RefCounted
## Shared helpers for writing archive entries into the cache.
## Archives are untrusted, so every entry path is checked before anything is written.


## True when the entry equals one of the prefixes or sits under one ending in "/".
static func is_wanted(entry: String, prefixes: Array) -> bool:
	for prefix: String in prefixes:
		if entry == prefix or (prefix.ends_with("/") and entry.begins_with(prefix)):
			return true
	return false


## Rejects absolute paths, drive letters, backslashes and any ".." segment.
static func is_safe_path(entry: String) -> bool:
	if entry.is_empty() or entry.begins_with("/") or entry.contains("\\") or entry.contains(":"):
		return false
	for part in entry.split("/"):
		if part == "..":
			return false
	return true


## Writes bytes to out_dir/entry. Returns an error message, or "" on success.
## Pass the same made_dirs dictionary for every entry of an archive: creating a folder costs
## about 20 ms even when it already exists, which dominates extracting thousands of files.
static func write(out_dir: String, entry: String, bytes: PackedByteArray, made_dirs := {}) -> String:
	if not is_safe_path(entry):
		return "refusing unsafe archive path '%s'" % entry
	var target := out_dir.path_join(entry)
	var folder := target.get_base_dir()
	if not made_dirs.has(folder):
		var err := DirAccess.make_dir_recursive_absolute(folder)
		if err != OK:
			return "cannot create %s (%s)" % [folder, error_string(err)]
		made_dirs[folder] = true
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return "cannot write %s (%s)" % [target, error_string(FileAccess.get_open_error())]
	file.store_buffer(bytes)
	file.close()
	return ""
