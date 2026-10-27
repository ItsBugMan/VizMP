extends SceneTree
## Real decoder -> Master FFT -> stereo PCM, plus filesystem/library entry points.
const LOADER = preload("res://scripts/audio/AudioStreamLoader.gd")
const FIXTURE = "res://tests/fixtures/stereo-tones.flac"
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1

func run() -> void:
	await process_frame
	check(ClassDB.class_exists(&"AudioStreamFLAC"), "Native AudioStreamFLAC registered")
	# Outside res:// and with uppercase suffix: no import database dependency.
	var folder := OS.get_user_data_dir().path_join("flac-smoke")
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("stereo-tones.FLAC")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes(FIXTURE))
	file.close()
	var stream: AudioStream = LOADER.load_file(path)
	check(stream != null and stream.get_class() == "AudioStreamFLAC", "External uppercase FLAC loads without import")
	if stream == null:
		push_error(LOADER.last_error)
		quit(1)
		return
	check(absf(stream.get_length() - 3.0) < 0.01, "Native duration reports three seconds")
	check(LOADER.load_file(folder.path_join("missing.flac")) == null, "Missing FLAC is rejected")
	var broken := folder.path_join("broken.flac")
	file = FileAccess.open(broken, FileAccess.WRITE)
	file.store_string("not FLAC")
	file.close()
	check(LOADER.load_file(broken) == null, "Invalid FLAC is rejected")
	DirAccess.remove_absolute(broken)
	var main: Control = load("res://scenes/Main.tscn").instantiate()
	main.save_layout_enabled = false
	root.add_child(main)
	await process_frame
	main._on_files_dropped(PackedStringArray([path]))
	check(main._player.stream != null and main._player.stream.get_class() == "AudioStreamFLAC" and main._playlist.paths.has(path), "Drop loads and queues FLAC")
	check(main._dialog.filters[0].contains("*.flac"), "File explorer includes FLAC")
	var library: Node = main._layout.panels.library.content.get_child(0)
	library.folders = PackedStringArray([folder])
	library.scan()
	for i in range(10): await process_frame
	check(library._paths.has(path), "Media library discovers external FLAC")
	library.track_requested.emit(path)
	check(main._player.playing, "Library selection plays FLAC")
	var analyzer := root.get_node("AudioAnalyzer")
	var pcm := root.get_node("StereoPCM")
	pcm.acquire(main)
	await create_timer(0.55).timeout
	check(analyzer.spectrum.size() == 64 and analyzer.volume > 0.1, "Decoded FLAC drives 64-bin Master FFT")
	var left: Vector2 = analyzer._instance.get_magnitude_for_frequency_range(190, 250)
	var right: Vector2 = analyzer._instance.get_magnitude_for_frequency_range(1700, 1820)
	check(left.x > left.y * 4.0 and right.y > right.x * 4.0, "FFT preserves independent left/right tones")
	check(pcm.texture_frame_count > 0 and pcm.rms.x > 0.05 and pcm.rms.y > 0.05, "Stereo scope receives decoded FLAC PCM")
	main._player.stream_paused = true
	main._transport.seek_to(1.5)
	await create_timer(0.1).timeout
	check(main._player.stream_paused and absf(main._player.get_playback_position() - 1.5) < 0.1, "FLAC seek preserves pause")
	pcm.release(main)
	main._player.stop()
	main._player.stream = null
	main.queue_free()
	await process_frame
	var saver: Control = load("res://scenes/Screensaver.tscn").instantiate()
	saver.configure_display = false
	saver.start_audio = false
	root.add_child(saver)
	var found: Array[String] = await saver.scan_directory(folder, true)
	check(found.has(path), "Screensaver scanner discovers FLAC")
	saver.playlist.assign([path])
	saver._play_next()
	check(saver.player.playing and saver.player.stream.get_class() == "AudioStreamFLAC", "Screensaver plays native FLAC")
	saver.player.stop()
	saver.player.stream = null
	saver.queue_free()
	stream = null
	await create_timer(0.15).timeout
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(folder)
	print("Failures: ", failures)
	quit(0 if failures == 0 else 1)
