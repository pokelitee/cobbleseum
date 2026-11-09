extends TestCase


func _source(archive_bytes: PackedByteArray, archive := "zip") -> Dictionary:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(archive_bytes)
	return {
		"version": "1.0",
		"url": "https://example.invalid/a." + archive,
		"size": archive_bytes.size(),
		"sha256": digest.finish().hex_encode(),
		"archive": archive,
		"license": "test",
		"extract": ["data/"],
		"layout": [{"pattern": "data/*.json", "min_count": 2, "format_key": "format_version", "format_value": "1.0"}],
	}


func _zip(entries: Dictionary) -> PackedByteArray:
	var path := TestFiles.fresh_dir("zip_build").path_join("a.zip")
	var zip := ZIPPacker.new()
	zip.open(path)
	for name: String in entries:
		zip.start_file(name)
		zip.write_file(str(entries[name]).to_utf8_buffer())
		zip.close_file()
	zip.close()
	return FileAccess.get_file_as_bytes(path)


## A pipeline whose cache already holds the given archive, as if fetch had succeeded.
func _cached_pipeline(name: String, bytes: PackedByteArray, source: Dictionary) -> AssetPipeline:
	var pipeline := AssetPipeline.new(TestFiles.fresh_dir(name).path_join("cache"))
	pipeline.prepare_cache()
	var download := pipeline.cache_dir.path_join("download.part")
	var file := FileAccess.open(download, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	assert_eq(pipeline.store_download("test", source, download), "")
	return pipeline


func test_validate_source_reports_missing_and_bad_fields() -> void:
	var good := _source("x".to_utf8_buffer())
	assert_eq(AssetPipeline.validate_source("s", good), "")
	var missing := good.duplicate()
	missing.erase("sha256")
	assert_true(AssetPipeline.validate_source("s", missing).contains("missing \"sha256\""))
	var bad_hash := good.duplicate()
	bad_hash.sha256 = "abc"
	assert_true(AssetPipeline.validate_source("s", bad_hash).contains("sha256"))
	var bad_type := good.duplicate()
	bad_type.archive = "rar"
	assert_true(AssetPipeline.validate_source("s", bad_type).contains("archive type"))


func test_committed_manifest_is_valid() -> void:
	var manifest := AssetPipeline.load_manifest("res://sources.json")
	assert_false(manifest.has("error"), str(manifest.get("error", "")))
	assert_true(manifest.get("sources", {}).has("showdown"))
	assert_true(manifest.get("sources", {}).has("cobblemon"))


func test_prepare_cache_adds_gdignore() -> void:
	var pipeline := AssetPipeline.new(TestFiles.fresh_dir("gdignore").path_join("cache"))
	assert_eq(pipeline.prepare_cache(), "")
	assert_true(FileAccess.file_exists(pipeline.cache_dir.path_join(".gdignore")))


func test_store_download_discards_wrong_checksum() -> void:
	var source := _source("expected".to_utf8_buffer())
	var pipeline := AssetPipeline.new(TestFiles.fresh_dir("bad_sha").path_join("cache"))
	var download := pipeline.cache_dir.path_join("x.part")
	TestFiles.write_text(download, "tampered")  # same length as "expected"
	var err := pipeline.store_download("test", source, download)
	assert_true(err.contains("SHA-256 mismatch"), err)
	assert_false(FileAccess.file_exists(download))
	assert_false(FileAccess.file_exists(pipeline.archive_path(source)))


func test_store_download_discards_wrong_size() -> void:
	var source := _source("expected".to_utf8_buffer())
	var pipeline := AssetPipeline.new(TestFiles.fresh_dir("bad_size").path_join("cache"))
	var download := pipeline.cache_dir.path_join("x.part")
	TestFiles.write_text(download, "short")
	assert_true(pipeline.store_download("test", source, download).contains("expected 8"))
	assert_false(FileAccess.file_exists(download))


func test_offline_fetch_fails_clearly_when_not_cached() -> void:
	var pipeline := AssetPipeline.new(TestFiles.fresh_dir("offline").path_join("cache"), true)
	var err: String = await pipeline.fetch("test", _source("x".to_utf8_buffer()), null)
	assert_true(err.contains("--offline"), err)


const GOOD_JSON := "{\"format_version\": \"1.0\"}"


func test_extract_keeps_wanted_entries_and_skips_when_stamp_matches() -> void:
	var bytes := _zip({"data/a.json": GOOD_JSON, "data/b.json": GOOD_JSON, "other/c.txt": "c"})
	var source := _source(bytes)
	var pipeline := _cached_pipeline("extract", bytes, source)
	assert_eq(pipeline.extract("test", source), "")
	var out := pipeline.source_dir("test", source)
	assert_eq(AssetPipeline.indexed_files(out), PackedStringArray(["data/a.json", "data/b.json"]))

	TestFiles.write_text(out.path_join("data/marker.txt"), "left alone")
	assert_eq(pipeline.extract("test", source), "")
	assert_true(FileAccess.file_exists(out.path_join("data/marker.txt")), "second run should be skipped")

	source.extract = ["data/", "other/"]
	assert_eq(pipeline.extract("test", source), "")
	assert_false(FileAccess.file_exists(out.path_join("data/marker.txt")), "changed inputs should re-extract")
	assert_true(FileAccess.file_exists(out.path_join("other/c.txt")))


func test_layout_failure_explains_and_leaves_nothing_cached() -> void:
	var bytes := _zip({"data/a.json": GOOD_JSON, "data/b.json": GOOD_JSON})
	var source := _source(bytes)
	var pipeline := _cached_pipeline("layout", bytes, source)
	source.layout = [{"pattern": "data/*.json", "min_count": 3}]
	var err := pipeline.extract("test", source)
	assert_true(err.contains("expected at least 3 files matching 'data/*.json', found 2"), err)
	assert_true(err.contains("upstream layout may have changed"), err)
	assert_false(DirAccess.dir_exists_absolute(pipeline.source_dir("test", source)))
	assert_false(DirAccess.dir_exists_absolute(pipeline.source_dir("test", source) + ".tmp"))


func test_layout_checks_format_versions() -> void:
	var bytes := _zip({"data/a.json": GOOD_JSON, "data/b.json": "{\"format_version\": \"2.0\"}"})
	var source := _source(bytes)
	var pipeline := _cached_pipeline("format", bytes, source)
	var err := pipeline.extract("test", source)
	assert_true(err.contains("data/b.json has format_version \"2.0\", expected \"1.0\""), err)
