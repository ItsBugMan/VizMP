extends SceneTree
## Run with --headless --path <project> --script res://tests/audio_smoke.gd
## Verifies initialization, silent output, real FFT response and onset gates.
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
	var analyzer: Node = root.get_node("AudioAnalyzer")
	_check(analyzer.is_ready, "Master spectrum effect initialized")
	_check(analyzer.spectrum.size() == 64, "64 persistent spectrum bins")
	_check(analyzer.frequency_edges.size() == 65, "65 logarithmic frequency boundaries")
	await create_timer(0.2).timeout
	_check(is_zero_approx(analyzer.volume), "Silence maps to zero")
	# Deterministic detector inputs test gates independently of audio hardware.
	analyzer.reset_history()
	for i in range(30):
		analyzer._clock += 1.0 / 60.0
		analyzer._detect_beat(0.001, 1.0 / 60.0)
	analyzer._detect_beat(0.15, 1.0 / 60.0)
	_check(analyzer.beat_pulse > 0.0, "Rising transient produces a beat")
	var beat_time: float = analyzer._last_beat
	analyzer._detect_beat(0.0, 1.0 / 60.0)
	analyzer._detect_beat(0.3, 1.0 / 60.0)
	_check(analyzer._last_beat == beat_time, "Cooldown rejects immediate retrigger")
	analyzer.reset_history()
	# A real stereo 220 Hz PCM stream exercises the bus, not mocked FFT data.
	# Reordering effects while the FFT is silent must not retire its reader.
	var eq := AudioEffectEQ6.new()
	AudioServer.add_bus_effect(AudioServer.get_bus_index(&"Master"), eq, 0)
	var data := PackedByteArray()
	data.resize(44100 * 2 * 2)
	for frame in range(44100):
		var sample: int = int(sin(TAU * 220.0 * float(frame) / 44100.0) * 4000.0)
		data.encode_s16(frame * 4, sample)
		data.encode_s16(frame * 4 + 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = true
	stream.mix_rate = 44100
	stream.data = data
	var player := AudioStreamPlayer.new()
	root.add_child(player)
	player.stream = stream
	player.play()
	await create_timer(0.5).timeout
	_check(analyzer.bass > 0.1, "220 Hz reaches the FFT after inserting an EQ before it")
	_check(analyzer.bass > analyzer.highs, "Bass tone exceeds high-frequency energy")
	player.stop()
	player.stream = null
	stream = null
	player.queue_free()
	AudioServer.remove_bus_effect(AudioServer.get_bus_index(&"Master"), 0)
	# Let the audio mixer retire its last playback reference before teardown.
	await create_timer(0.1).timeout
	print("Failures: ", _failures)
	quit(0 if _failures == 0 else 1)
