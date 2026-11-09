class_name ZipReader
extends RefCounted
## Minimal zip extractor that reads the central directory once.
## Godot's ZIPReader looks each entry up from scratch, which takes seconds per file on a
## 40,000-entry jar; this reader extracts the whole Cobblemon subset in one pass.
## Supports stored and deflated entries; zip64 archives are rejected.

const END_OF_CENTRAL_DIR := 0x06054b50
const CENTRAL_ENTRY := 0x02014b50
const LOCAL_ENTRY := 0x04034b50
const STORED := 0
const DEFLATED := 8
## Gzip member header: magic, deflate method, no flags, zero mtime, no extra flags, unknown OS.
const GZIP_HEADER := [0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 0xff]


## Extracts the wanted entries of a zip file, appending each written path to `written`.
## Returns an error message, or "" on success.
static func extract(path: String, prefixes: Array, out_dir: String, written: Array = []) -> String:
	var data := FileAccess.get_file_as_bytes(path)
	if data.is_empty():
		return "cannot read %s" % path
	var eocd := _find_end_of_central_dir(data)
	if eocd < 0:
		return "%s is not a zip archive (no end-of-central-directory record)" % path
	var count := data.decode_u16(eocd + 10)
	var offset := data.decode_u32(eocd + 16)
	if count == 0xffff or offset == 0xffffffff:
		return "%s is a zip64 archive, which isn't supported" % path
	DirAccess.make_dir_recursive_absolute(out_dir)
	var made_dirs := {}
	for i in count:
		if offset + 46 > data.size() or data.decode_u32(offset) != CENTRAL_ENTRY:
			return "corrupt zip central directory at byte %d" % offset
		var method := data.decode_u16(offset + 10)
		var crc := data.decode_u32(offset + 16)
		var packed_size := data.decode_u32(offset + 20)
		var size := data.decode_u32(offset + 24)
		var name_length := data.decode_u16(offset + 28)
		var name := data.slice(offset + 46, offset + 46 + name_length).get_string_from_utf8()
		var local := data.decode_u32(offset + 42)
		offset += 46 + name_length + data.decode_u16(offset + 30) + data.decode_u16(offset + 32)
		if name.ends_with("/") or not ArchiveFiles.is_wanted(name, prefixes):
			continue
		var bytes := _read_entry(data, local, method, crc, packed_size, size)
		if bytes.is_empty() and size > 0:
			return "cannot decompress zip entry '%s' (method %d)" % [name, method]
		var err := ArchiveFiles.write(out_dir, name, bytes, made_dirs)
		if not err.is_empty():
			return err
		written.append(name)
	return ""


static func _find_end_of_central_dir(data: PackedByteArray) -> int:
	# The record is 22 bytes plus a comment of up to 65,535 bytes at the end of the file.
	var lowest := maxi(0, data.size() - 22 - 0xffff)
	for i in range(data.size() - 22, lowest - 1, -1):
		if data.decode_u32(i) == END_OF_CENTRAL_DIR:
			return i
	return -1


static func _read_entry(data: PackedByteArray, local: int, method: int, crc: int, packed_size: int, size: int) -> PackedByteArray:
	if local + 30 > data.size() or data.decode_u32(local) != LOCAL_ENTRY:
		return PackedByteArray()
	var start := local + 30 + data.decode_u16(local + 26) + data.decode_u16(local + 28)
	if start + packed_size > data.size():
		return PackedByteArray()
	var packed := data.slice(start, start + packed_size)
	if size == 0:
		return PackedByteArray()
	if method == STORED:
		return packed
	if method != DEFLATED:
		return PackedByteArray()
	# Godot only inflates zlib or gzip streams, so wrap the raw deflate data in a gzip member
	# whose trailer carries the CRC-32 and size from the central directory.
	var trailer := PackedByteArray()
	trailer.resize(8)
	trailer.encode_u32(0, crc)
	trailer.encode_u32(4, size)
	return (PackedByteArray(GZIP_HEADER) + packed + trailer).decompress(size, FileAccess.COMPRESSION_GZIP)
