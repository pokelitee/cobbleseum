class_name TestFiles
extends RefCounted
## Helpers for tests that need scratch folders and small synthetic archives.


## An empty folder under the user data directory, recreated on every call.
static func fresh_dir(name: String) -> String:
	var dir := ProjectSettings.globalize_path("user://test_tmp").path_join(name)
	AssetPipeline._remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


static func write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## One tar entry (header plus padded body). Only the fields the reader uses are filled in.
static func tar_entry(name: String, body: PackedByteArray, type := "0") -> PackedByteArray:
	var header := PackedByteArray()
	header.resize(TarReader.BLOCK)
	_put(header, 0, name.to_utf8_buffer())
	_put(header, 124, ("%011o" % body.size()).to_ascii_buffer())
	header[156] = type.unicode_at(0)
	_put(header, 257, "ustar".to_ascii_buffer())
	var padded := body.duplicate()
	padded.resize((body.size() + TarReader.BLOCK - 1) / TarReader.BLOCK * TarReader.BLOCK)
	return header + padded


static func tar_end() -> PackedByteArray:
	var end := PackedByteArray()
	end.resize(TarReader.BLOCK * 2)
	return end


static func _put(target: PackedByteArray, offset: int, bytes: PackedByteArray) -> void:
	for i in bytes.size():
		target[offset + i] = bytes[i]
