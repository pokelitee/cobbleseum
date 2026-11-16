extends TestCase

const SAMPLE_COUNT := 120
const LOOP_END := 100
## A square wave with a 10-sample period: 4800 Hz at 48 kHz, its root key C4.
const PERIOD := 10


## A minimal SoundFont: one preset (bank 0, program 0) whose instrument plays one looping
## sample for keys 48 to 84, skipping `start_offset` samples of it.
static func _bank(start_offset := 0) -> PackedByteArray:
	var sample := PackedByteArray()
	sample.resize(SAMPLE_COUNT * 2)
	for i in SAMPLE_COUNT:
		sample.encode_s16(i * 2, 16000 if (i % PERIOD) < PERIOD / 2 else -16000)
	var phdr := _record("Test", 20) + _u16(0) + _u16(0) + _u16(0) + _u32(0) + _u32(0) + _u32(0)
	phdr += _record("EOP", 20) + _u16(0) + _u16(0) + _u16(1) + _u32(0) + _u32(0) + _u32(0)
	var pbag := _u16(0) + _u16(0) + _u16(1) + _u16(0)
	var pgen := _gen(41, 0) + _gen(0, 0)
	var inst := _record("Inst", 20) + _u16(0) + _record("EOI", 20) + _u16(1)
	var gens := _range(43, 48, 84) + _gen(54, 1) + _gen(58, 60)
	if start_offset != 0:
		gens += _gen(0, start_offset)
	var ibag := _u16(0) + _u16(0) + _u16(gens.size() / 4 + 1) + _u16(0)
	var igen := gens + _gen(53, 0) + _gen(0, 0)
	var shdr := _record("Square", 20) + _u32(0) + _u32(SAMPLE_COUNT) + _u32(0) + _u32(LOOP_END) + _u32(48000)
	shdr += PackedByteArray([60, 0]) + _u16(0) + _u16(1)
	shdr += _record("EOS", 20) + _u32(0) + _u32(0) + _u32(0) + _u32(0) + _u32(0) + PackedByteArray([0, 0]) + _u16(0) + _u16(0)
	var empty_mod := PackedByteArray()
	empty_mod.resize(10)
	var pdta := "pdta".to_ascii_buffer() + _chunk("phdr", phdr) + _chunk("pbag", pbag) + _chunk("pmod", empty_mod) \
		+ _chunk("pgen", pgen) + _chunk("inst", inst) + _chunk("ibag", ibag) + _chunk("imod", empty_mod) \
		+ _chunk("igen", igen) + _chunk("shdr", shdr)
	var sdta := "sdta".to_ascii_buffer() + _chunk("smpl", sample)
	var body := "sfbk".to_ascii_buffer() + _chunk("LIST", sdta) + _chunk("LIST", pdta)
	return _chunk("RIFF", body)


static func _chunk(id: String, data: PackedByteArray) -> PackedByteArray:
	var out := id.to_ascii_buffer() + _u32(data.size()) + data
	if data.size() % 2 == 1:
		out.append(0)
	return out


static func _record(name: String, size: int) -> PackedByteArray:
	var out := name.to_ascii_buffer()
	out.resize(size)
	return out


static func _u16(value: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(2)
	out.encode_u16(0, value)
	return out


static func _u32(value: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, value)
	return out


static func _gen(operator: int, amount: int) -> PackedByteArray:
	var out := _u16(operator)
	out.resize(4)
	out.encode_s16(2, amount)
	return out


static func _range(operator: int, low: int, high: int) -> PackedByteArray:
	return _u16(operator) + PackedByteArray([low, high])


func _font(start_offset := 0) -> SoundFont:
	var path := TestFiles.fresh_dir("sound_font").path_join("test.sf2")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(_bank(start_offset))
	file.close()
	var font := SoundFont.new()
	assert_eq(font.load_file(path), "")
	return font


## Samples between rising zero crossings, averaged over the note's start.
static func _period(samples: PackedFloat32Array) -> float:
	var crossings: Array[int] = []
	for i in range(1, mini(samples.size(), 2000)):
		if samples[i - 1] <= 0.0 and samples[i] > 0.0:
			crossings.append(i)
	return float(crossings[-1] - crossings[0]) / (crossings.size() - 1)


func test_reads_presets() -> void:
	var font := _font()
	assert_true(font.has_preset(0, 0))
	assert_false(font.has_preset(0, 1))
	assert_eq(font.preset_name(0, 0), "Test")


func test_notes_are_pitched_from_the_root_key() -> void:
	var font := _font()
	font.rate = 48000
	assert_almost_eq(_period(font.note(0, 0, 60, 127, 0.05)[0]), PERIOD, 0.2, "the root key plays the sample as recorded")
	assert_almost_eq(_period(font.note(0, 0, 72, 127, 0.05)[0]), PERIOD / 2.0, 0.2, "an octave up halves the period")


func test_start_offsets_skip_the_start_of_the_sample() -> void:
	var plain: PackedFloat32Array = _font().note(0, 0, 60, 127, 0.05)[0]
	var skipped: PackedFloat32Array = _font(PERIOD / 2).note(0, 0, 60, 127, 0.05)[0]
	# Sample 60 is past the default 1 ms envelope delay, and a whole number of periods in.
	assert_true(plain[60] > 0.0, "the square is high at the start of each period")
	assert_true(skipped[60] < 0.0, "skipping half a period makes it low there")


func test_looping_samples_sustain_past_their_length() -> void:
	var font := _font()
	var note := font.note(0, 0, 60, 127, 0.1)
	assert_true(note[0].size() >= int(0.1 * 48000), "a 0.1 s note outlasts its 120-sample recording")


func test_key_ranges_and_missing_presets_give_silence() -> void:
	var font := _font()
	assert_eq(font.zones(0, 0, 30, 100).size(), 0, "below the key range")
	assert_eq(font.zones(0, 0, 60, 100).size(), 1)
	assert_eq(font.note(0, 5, 60, 100, 0.1)[0].size(), 0)


func test_rejects_other_files() -> void:
	var path := TestFiles.fresh_dir("sound_font_bad").path_join("x.sf2")
	TestFiles.write_text(path, "not a bank")
	assert_true(SoundFont.new().load_file(path).contains("not a SoundFont"))
