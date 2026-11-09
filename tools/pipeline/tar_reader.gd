class_name TarReader
extends RefCounted
## Minimal reader for gzip-compressed tar archives such as npm tarballs.
## Supports ustar names with prefixes and pax "path" records; other entry types are skipped.

const BLOCK := 512


## Extracts the wanted entries of a .tgz file, appending each written path to `written`.
## Returns an error message, or "" on success.
static func extract_tgz(path: String, prefixes: Array, out_dir: String, written: Array = []) -> String:
	var compressed := FileAccess.get_file_as_bytes(path)
	if compressed.is_empty():
		return "cannot read %s" % path
	var data := compressed.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	if data.is_empty():
		return "%s is not valid gzip data" % path
	return extract_tar(data, prefixes, out_dir, written)


static func extract_tar(data: PackedByteArray, prefixes: Array, out_dir: String, written: Array = []) -> String:
	var offset := 0
	var pax_path := ""
	var made_dirs := {}
	while offset + BLOCK <= data.size():
		var header := data.slice(offset, offset + BLOCK)
		if header.count(0) == BLOCK:
			break
		var size := _parse_octal(header.slice(124, 136))
		if size < 0:
			return "corrupt tar header at byte %d" % offset
		var name := _read_text(header.slice(0, 100))
		var prefix := _read_text(header.slice(345, 500))
		if not prefix.is_empty():
			name = prefix + "/" + name
		var type := "0" if header[156] == 0 else char(header[156])
		var body_start := offset + BLOCK
		if body_start + size > data.size():
			return "truncated tar entry '%s'" % name
		var body := data.slice(body_start, body_start + size)
		offset = body_start + (size + BLOCK - 1) / BLOCK * BLOCK

		if type == "x":
			pax_path = _pax_path(body)
		elif type == "0" or type == "7":
			if not pax_path.is_empty():
				name = pax_path
				pax_path = ""
			if ArchiveFiles.is_wanted(name, prefixes):
				var err := ArchiveFiles.write(out_dir, name, body, made_dirs)
				if not err.is_empty():
					return err
				written.append(name)
		elif type != "g":
			pax_path = ""
	return ""


static func _read_text(bytes: PackedByteArray) -> String:
	var end := bytes.find(0)
	return (bytes if end < 0 else bytes.slice(0, end)).get_string_from_utf8()


## Parses a NUL- or space-terminated octal field; returns -1 when it isn't octal.
static func _parse_octal(bytes: PackedByteArray) -> int:
	var text := _read_text(bytes).strip_edges()
	var value := 0
	for digit in text:
		if digit < "0" or digit > "7":
			return -1
		value = value * 8 + int(digit)
	return value


## Pax records look like "<length> <key>=<value>\n".
static func _pax_path(body: PackedByteArray) -> String:
	for record in body.get_string_from_utf8().split("\n", false):
		var space := record.find(" ")
		if space >= 0 and record.substr(space + 1).begins_with("path="):
			return record.substr(space + 6)
	return ""
