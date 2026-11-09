extends TestCase


func test_is_wanted_matches_exact_files_and_folder_prefixes() -> void:
	var prefixes := ["package/dist/data/moves.js", "assets/pokemon/"]
	assert_true(ArchiveFiles.is_wanted("package/dist/data/moves.js", prefixes))
	assert_true(ArchiveFiles.is_wanted("assets/pokemon/0001/a.json", prefixes))
	assert_false(ArchiveFiles.is_wanted("package/dist/data/moves.js.map", prefixes))
	assert_false(ArchiveFiles.is_wanted("assets/pokemonx/a.json", prefixes))


func test_is_safe_path_rejects_escapes() -> void:
	assert_true(ArchiveFiles.is_safe_path("a/b/c.json"))
	for unsafe in ["", "../x", "a/../../b", "/etc/passwd", "C:/x", "a\\b"]:
		assert_false(ArchiveFiles.is_safe_path(unsafe), unsafe)


func test_write_refuses_unsafe_paths() -> void:
	var dir := TestFiles.fresh_dir("archive_files")
	var err := ArchiveFiles.write(dir, "../escape.txt", "x".to_utf8_buffer())
	assert_true(err.begins_with("refusing unsafe archive path"))
	assert_false(FileAccess.file_exists(dir.get_base_dir().path_join("escape.txt")))
