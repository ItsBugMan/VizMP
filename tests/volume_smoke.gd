extends SceneTree
## Uses a dedicated settings file; never writes the user's volume preferences.
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS: " if ok else "FAIL: ", label)
	if not ok: failures += 1

func run() -> void:
	await process_frame
	var output := root.get_node("AudioOutput")
	var original_path: String = output.settings_path
	var original_volume: float = output.get_volume_percent()
	var original_mute: bool = output.muted
	output.settings_path = "res://.godot/volume-smoke.cfg"
	var config := ConfigFile.new()
	config.set_value("other", "keep", "preserved")
	config.save(output.settings_path)
	var master: int = AudioServer.get_bus_index(&"Master")
	output.set_volume_percent(50.0)
	output.set_muted(false)
	check(absf(AudioServer.get_bus_volume_db(master) - linear_to_db(0.5)) < 0.001, "50% uses logarithmic -6.02 dB gain")
	check(absf(db_to_linear(AudioServer.get_bus_volume_db(master)) - 0.5) < 0.001, "dB converts back to the selected linear gain")
	output.set_muted(true)
	check(AudioServer.is_bus_mute(master) and output.get_volume_percent() == 50.0, "Mute silences Master without changing the slider")
	output.set_volume_percent(25.0)
	check(AudioServer.is_bus_mute(master) and output.get_volume_percent() == 25.0, "Adjusting muted volume retains mute")
	output.set_muted(false)
	check(not AudioServer.is_bus_mute(master) and absf(AudioServer.get_bus_volume_db(master) - linear_to_db(0.25)) < 0.001, "Unmute restores the selected level")
	output.set_volume_percent(0.0)
	check(AudioServer.is_bus_mute(master) and is_finite(AudioServer.get_bus_volume_db(master)), "0% is exact silence with finite bus gain")
	output.set_volume_percent(100.0)
	check(not AudioServer.is_bus_mute(master) and is_zero_approx(AudioServer.get_bus_volume_db(master)), "Raising zero volume restores output at unity gain")
	output.set_volume_percent(37.0)
	output.set_muted(true)
	await create_timer(0.3).timeout
	config.load(output.settings_path)
	check(is_equal_approx(config.get_value("audio", "volume_linear"), 0.37) and config.get_value("audio", "muted"), "Changes autosave volume and mute")
	check(config.get_value("other", "keep") == "preserved", "Audio saves preserve other settings sections")
	# Reload through a fresh owner to verify startup rather than cached state.
	var restored := preload("res://scripts/audio/AudioOutput.gd").new()
	restored.settings_path = output.settings_path
	root.add_child(restored)
	check(is_equal_approx(restored.get_volume_percent(), 37.0) and restored.muted and AudioServer.is_bus_mute(master), "Fresh instance restores volume and mute before playback")
	restored.set_volume_percent(63.0)
	restored.free()
	config.load(output.settings_path)
	check(is_equal_approx(config.get_value("audio", "volume_linear"), 0.63), "Immediate shutdown flushes the pending save")
	var main: Control = load("res://scenes/Main.tscn").instantiate()
	main.save_layout_enabled = false
	root.add_child(main)
	var transport: Node = main._transport
	transport.volume_slider.value = 42.0
	transport.mute_button.button_pressed = false
	check(output.get_volume_percent() == 42.0 and not output.muted and transport._volume_label.text == "42%", "Transport slider, mute and percentage stay synchronized")
	var loopback := root.get_node("AudioLoopbackManager")
	# The mode signal tests UI state without opening the physical WASAPI device.
	loopback.mode = loopback.Mode.DESKTOP
	loopback.mode_changed.emit(loopback.mode)
	check(not transport.volume_slider.editable and transport.mute_button.disabled and transport._desktop_volume_note.visible, "Desktop mode identifies saved file volume and disables its controls")
	var bus: int = AudioServer.get_bus_index(&"DesktopAnalysis")
	var sink: int = AudioServer.get_bus_index(&"DesktopSilentSink")
	var desktop_gain: float = AudioServer.get_bus_volume_db(bus)
	var sink_mute: bool = AudioServer.is_bus_mute(sink)
	var capture := AudioServer.get_bus_effect(bus, 0) as AudioEffectCapture
	var analyzer := root.get_node("AudioAnalyzer")
	analyzer.set_analysis_bus(&"DesktopAnalysis")
	var player := AudioStreamPlayer.new()
	player.bus = &"DesktopAnalysis"
	player.stream = preload("res://scripts/audio/AudioStreamLoader.gd").load_file("res://tests/fixtures/stereo-tones.flac")
	root.add_child(player)
	player.play()
	await create_timer(0.25).timeout
	var before: Vector2 = analyzer._instance.get_magnitude_for_frequency_range(190.0, 250.0)
	capture.clear_buffer()
	output.set_volume_percent(0.0)
	output.set_muted(true)
	await create_timer(0.15).timeout
	var after: Vector2 = analyzer._instance.get_magnitude_for_frequency_range(190.0, 250.0)
	var frames: PackedVector2Array = capture.get_buffer(capture.get_frames_available())
	var peak: float = 0.0
	for frame in frames: peak = maxf(peak, absf(frame.x))
	check(before.x > 0.01 and absf(before.x - after.x) / before.x < 0.05, "Master zero/mute leaves desktop FFT amplitude unchanged")
	check(peak > 0.1 and AudioServer.get_bus_volume_db(bus) == desktop_gain and AudioServer.is_bus_mute(sink) == sink_mute, "Desktop PCM and silent-sink routing remain intact")
	player.stop()
	player.stream = null
	player.queue_free()
	loopback.mode = loopback.Mode.FILE
	loopback.mode_changed.emit(loopback.mode)
	analyzer.set_analysis_bus(&"Master")
	check(transport.volume_slider.editable and not transport.mute_button.disabled and not transport._desktop_volume_note.visible, "File controls return after leaving desktop mode")
	main.queue_free()
	await process_frame
	# Restore runtime state while all test writes still target the isolated file.
	output.set_volume_percent(original_volume)
	output.set_muted(original_mute)
	output.save_settings()
	output.settings_path = original_path
	DirAccess.remove_absolute("res://.godot/volume-smoke.cfg")
	await create_timer(0.1).timeout
	print("Failures: ", failures)
	quit(0 if failures == 0 else 1)
