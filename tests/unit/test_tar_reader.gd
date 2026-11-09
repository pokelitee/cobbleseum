extends TestCase


func test_extracts_only_wanted_entries() -> void:
	var dir := TestFiles.fresh_dir("tar_wanted")
	var tar := TestFiles.tar_entry("package/dist/data/moves.js", "moves".to_utf8_buffer()) \
		+ TestFiles.tar_entry("package/README.md", "readme".to_utf8_buffer()) \
		+ TestFiles.tar_end()
	assert_eq(TarReader.extract_tar(tar, ["package/dist/"], dir), "")
	assert_eq(FileAccess.get_file_as_string(dir.path_join("package/dist/data/moves.js")), "moves")
	assert_false(FileAccess.file_exists(dir.path_join("package/README.md")))


func test_pax_path_overrides_next_entry_name() -> void:
	var dir := TestFiles.fresh_dir("tar_pax")
	var long_name := "package/" + "x".repeat(120) + ".json"
	var record := "%d path=%s\n" % [0, long_name]
	record = "%d path=%s\n" % [record.length() + 1, long_name]
	var tar := TestFiles.tar_entry("PaxHeader", record.to_utf8_buffer(), "x") \
		+ TestFiles.tar_entry("truncated-name", "{}".to_utf8_buffer()) \
		+ TestFiles.tar_end()
	assert_eq(TarReader.extract_tar(tar, ["package/"], dir), "")
	assert_true(FileAccess.file_exists(dir.path_join(long_name)))


func test_rejects_path_traversal() -> void:
	var dir := TestFiles.fresh_dir("tar_traversal")
	var tar := TestFiles.tar_entry("package/../../evil.txt", "x".to_utf8_buffer()) + TestFiles.tar_end()
	assert_true(TarReader.extract_tar(tar, ["package/"], dir).begins_with("refusing unsafe archive path"))


func test_reports_truncated_entry() -> void:
	var tar := TestFiles.tar_entry("package/a.txt", "abc".to_utf8_buffer()).slice(0, TarReader.BLOCK)
	assert_true(TarReader.extract_tar(tar, ["package/"], TestFiles.fresh_dir("tar_trunc")).begins_with("truncated"))


func test_reads_gzip_compressed_archives() -> void:
	var dir := TestFiles.fresh_dir("tar_gzip")
	var tar := TestFiles.tar_entry("package/a.txt", "hello".to_utf8_buffer()) + TestFiles.tar_end()
	var archive := dir.path_join("a.tgz")
	var file := FileAccess.open(archive, FileAccess.WRITE)
	file.store_buffer(tar.compress(FileAccess.COMPRESSION_GZIP))
	file.close()
	assert_eq(TarReader.extract_tgz(archive, ["package/"], dir.path_join("out")), "")
	assert_eq(FileAccess.get_file_as_string(dir.path_join("out/package/a.txt")), "hello")
