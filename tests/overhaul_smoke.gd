extends SceneTree
const META = preload("res://scripts/audio/AudioMetadata.gd")
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1
func write(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
func frame(id: String, value: String, sync: bool) -> PackedByteArray:
	var bytes := PackedByteArray([3])
	bytes.append_array(value.to_utf8_buffer())
	var header := id.to_ascii_buffer()
	var count := bytes.size()
	for shift in [21, 14, 7, 0] if sync else [24, 16, 8, 0]: header.append((count >> shift) & (127 if sync else 255))
	header.append_array(PackedByteArray([0, 0]))
	header.append_array(bytes)
	return header
func run() -> void:
	await process_frame
	for version in [3, 4]:
		var body := frame("TIT2", "Synthetic title", version == 4)
		body.append_array(frame("TPE1", "Test Artist", version == 4))
		body.append_array(frame("TALB", "Test Album", version == 4))
		var header := PackedByteArray([73, 68, 51, version, 0, 0])
		for shift in [21, 14, 7, 0]: header.append((body.size() >> shift) & 127)
		header.append_array(body)
		write("res://.godot/meta-test.mp3", header)
		var metadata := META.read_track("res://.godot/meta-test.mp3")
		check(metadata.title == "Synthetic title" and metadata.artist == "Test Artist" and metadata.album == "Test Album", "ID3v2.%d text frames" % version)
	write("res://.godot/meta-test.mp3", PackedByteArray([73, 68, 51, 4, 0, 0, 127, 127, 127, 127]))
	check(META.read_track("res://.godot/meta-test.mp3").title == "meta-test", "Truncated tag falls back safely")
	var main: Control = load("res://scenes/Main.tscn").instantiate()
	main.save_layout_enabled = false
	root.add_child(main)
	await process_frame
	check(main._layout.panels.has("library"), "Library is a fifth dockable panel")
	var fixture := AudioStreamWAV.new()
	fixture.mix_rate = 44100
	fixture.format = AudioStreamWAV.FORMAT_16_BITS
	var bytes := PackedByteArray()
	bytes.resize(44100 * 2 * 4)
	fixture.data = bytes
	fixture.save_to_wav("res://.godot/transport-test.wav")
	main._load_track("res://.godot/transport-test.wav")
	main._player.stream_paused = true
	main._transport.seek_to(2.0)
	await create_timer(0.1).timeout
	check(main._player.stream_paused and absf(main._player.get_playback_position() - 2.0) < 0.1, "Seek preserves pause and exact destination")
	check(root.get_node("AudioAnalyzer").beat_pulse == 0.0, "Seek clears transient history")
	main._transport.slider.value = 1.0
	await process_frame
	check(absf(main._player.get_playback_position() - 1.0) < 0.1, "Keyboard/click slider change seeks")
	# A shorter next track must not seek to its end when Range clamps the slider.
	main._transport.slider.set_value_no_signal(3.0)
	var short_track := AudioStreamWAV.new()
	short_track.mix_rate = 44100
	short_track.format = AudioStreamWAV.FORMAT_16_BITS
	var short_bytes := PackedByteArray()
	short_bytes.resize(88200)
	short_track.data = short_bytes
	main._player.stop()
	main._player.stream = short_track
	main._player.play()
	main._player.stream_paused = true
	main._transport._process(0.2)
	check(main._player.get_playback_position() < 0.1, "Shorter next track does not inherit old slider position")
	var library: Node = main._layout.panels.library.content.get_child(0)
	# Scan only a dedicated fixture folder without saving user preferences.
	DirAccess.make_dir_recursive_absolute("res://.godot/library-fixture/nested")
	fixture.save_to_wav("res://.godot/library-fixture/nested/track.wav")
	library.folders = PackedStringArray(["res://.godot/library-fixture", "res://.godot/library-fixture/nested"])
	library.scan()
	for i in range(10): await process_frame
	check(library._paths.size() == 1, "Recursive folder scan deduplicates overlapping roots")
	main._layout.detach_panel("visualizer")
	await process_frame
	var parent: Node = main._visualizer_host.get_parent()
	main.set_visualizer_fullscreen(true)
	await process_frame
	check(not main._layout.visible and main._visualizer_host.get_parent() == main and not main._layout.windows.visualizer.visible, "Fullscreen isolates visualizer and hides detached window")
	main.set_visualizer_fullscreen(false)
	await process_frame
	check(main._visualizer_host.get_parent() == parent and main._layout.visible and main._layout.windows.visualizer.visible, "Fullscreen restores original dock/window ownership")
	main._layout.dock_panel("visualizer", 2)
	for mode in range(1, 5):
		main._visualizer_host.set_mode(mode)
		for quality in range(3): main._visualizer_host.set_quality(quality)
		await process_frame
		check(main._visualizer_host._viewport.use_hdr_2d, "HDR viewport for visualizer %d" % mode)
	main.queue_free()
	await process_frame
	print("Failures: ", failures)
	quit(0 if failures == 0 else 1)
