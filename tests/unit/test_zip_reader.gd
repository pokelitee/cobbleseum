extends TestCase


func _make_zip(dir: String, entries: Dictionary) -> String:
	var path := dir.path_join("a.zip")
	var zip := ZIPPacker.new()
	zip.open(path)
	for name: String in entries:
		zip.start_file(name)
		zip.write_file(entries[name])
		zip.close_file()
	zip.close()
	return path


func test_extracts_deflated_entries_by_prefix() -> void:
	var dir := TestFiles.fresh_dir("zip_extract")
	var big := "abc".repeat(5000).to_utf8_buffer()
	var path := _make_zip(dir, {"keep/a.txt": big, "keep/empty.txt": PackedByteArray(), "skip/b.txt": "b".to_utf8_buffer()})
	assert_eq(ZipReader.extract(path, ["keep/"], dir.path_join("out")), "")
	assert_eq(FileAccess.get_file_as_bytes(dir.path_join("out/keep/a.txt")), big)
	assert_true(FileAccess.file_exists(dir.path_join("out/keep/empty.txt")))
	assert_false(FileAccess.file_exists(dir.path_join("out/skip/b.txt")))


func test_rejects_path_traversal() -> void:
	var dir := TestFiles.fresh_dir("zip_traversal")
	var path := _make_zip(dir, {"keep/../../evil.txt": "x".to_utf8_buffer()})
	assert_true(ZipReader.extract(path, ["keep/"], dir.path_join("out")).begins_with("refusing unsafe archive path"))


func test_reports_non_zip_files() -> void:
	var dir := TestFiles.fresh_dir("zip_bad")
	TestFiles.write_text(dir.path_join("not.zip"), "hello, not a zip")
	assert_true(ZipReader.extract(dir.path_join("not.zip"), ["a/"], dir).contains("not a zip archive"))
