extends SceneTree
## Windows integration test. Briefly plays audio in a SEPARATE Godot process.
## Use a quiet default output device for deterministic spectral assertions.

var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)
	else:
		print("PASS: ", label)

func _run() -> void:
	await process_frame
	var manager: Node = root.get_node("AudioLoopbackManager")
	var analyzer: Node = root.get_node("AudioAnalyzer")
	var pcm: Node = root.get_node("StereoPCM")
	var file_player := AudioStreamPlayer.new()
	root.add_child(file_player)
	var silent_stream := AudioStreamGenerator.new()
	file_player.stream = silent_stream
	file_player.play()
	manager.register_file_player(file_player)
	var error: Error = manager.set_mode(manager.Mode.DESKTOP)
	_check(error == OK, "Desktop mode starts")
	if error != OK:
		push_error(manager.status)
		quit(1)
		return
	_check(file_player.stream_paused, "File player pauses in desktop mode")
	pcm.acquire(root)
	var pid: int = OS.create_process(OS.get_executable_path(), PackedStringArray([
		"--headless", "--audio-driver", "WASAPI", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/loopback_tone.gd"]), false)
	_check(pid > 0, "Separate audio source process starts")
	var peak_bass: float = 0.0
	var left_bass: float = 0.0
	var right_bass: float = 0.0
	var peak_pcm: float = 0.0
	var captured: int = 0
	var shared_pcm_peak: float = 0.0
	var end: int = Time.get_ticks_msec() + 4500
	while Time.get_ticks_msec() < end:
		await process_frame
		peak_bass = maxf(peak_bass, analyzer.bass)
		shared_pcm_peak = maxf(shared_pcm_peak, pcm.peak)
		# Bin near 220 Hz; stereo source has 880 Hz only in right channel.
		for i in range(analyzer.BIN_COUNT):
			if analyzer.frequency_edges[i] <= 220 and analyzer.frequency_edges[i + 1] > 220:
				left_bass = maxf(left_bass, analyzer.spectrum_left[i])
				right_bass = maxf(right_bass, analyzer.spectrum_right[i])
		for sample in manager.pcm_frames:
			peak_pcm = maxf(peak_pcm, maxf(absf(sample.x), absf(sample.y)))
		captured = manager.received_frames
	_check(captured > 44100, "WASAPI transports external desktop PCM")
	_check(peak_pcm > 0.01, "AudioEffectCapture exposes nonzero signed PCM")
	_check(shared_pcm_peak > 0.01 and pcm.texture_frame_count > 0, "Desktop PCM reaches the shared oscilloscope texture service")
	_check(peak_bass > 0.1, "External 220 Hz signal drives existing bass analysis")
	_check(left_bass > right_bass + 0.05, "Stereo left/right frequency separation survives loopback")
	var master: int = AudioServer.get_bus_index(&"Master")
	var master_level: float = AudioServer.get_bus_peak_volume_left_db(master, 0)
	_check(master_level < -60.0, "Captured PCM never returns to Master output")
	var helper_pid: int = manager._pid
	manager.set_mode(manager.Mode.FILE)
	_check(pcm.texture_frame_count == 0, "Switching audio sources clears old phase samples")
	_check(not file_player.stream_paused, "Returning to file mode restores playback state")
	_check(not OS.is_process_running(helper_pid), "Mode switch terminates helper")
	_check(analyzer.is_ready, "Master FFT rebinds after desktop capture")
	file_player.stream_paused = true
	manager.set_mode(manager.Mode.DESKTOP)
	manager.set_mode(manager.Mode.FILE)
	_check(file_player.stream_paused, "Previously paused files remain paused after mode roundtrip")
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	manager.set_mode(manager.Mode.DESKTOP)
	OS.kill(manager._pid)
	await create_timer(0.8).timeout
	_check(manager.mode == manager.Mode.FILE, "Helper failure automatically restores file mode")
	_check(file_player.stream_paused, "Helper failure preserves the original paused state")
	pcm.release(root)
	file_player.queue_free()
	await process_frame
	print("Captured frames: ", captured, "; peak PCM: ", peak_pcm, "; peak bass: ", peak_bass)
	print("Failures: ", _failures)
	quit(0 if _failures == 0 else 1)
