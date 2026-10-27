extends SceneTree
## Forward+/D3D12 integration. Real stereo WAV passes through the audio bus;
## Master is muted after its capture tap, so the test does not play test tones.
## Use --audio-driver Dummy to validate stereo capture on surround endpoints.
var _failures: int = 0
var _player: AudioStreamPlayer
var _pcm: Node

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error(label)

func _tone(phase: float, right_amplitude: float = 1.0, right_frequency_ratio: float = 1.0) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(44100 * 2 * 4)
	for frame in range(44100 * 2):
		var angle: float = TAU * 220.0 * frame / 44100.0
		bytes.encode_s16(frame * 4, int(sin(angle) * 10000.0))
		bytes.encode_s16(frame * 4 + 2, int(sin(angle * right_frequency_ratio + phase) * 10000.0 * right_amplitude))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = true
	stream.mix_rate = 44100
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = 44100 * 2
	return stream

func _play(stream: AudioStreamWAV) -> void:
	_player.stop()
	_pcm.reset()
	_player.stream = stream
	_player.play()
	# Retire the previous stream's mixer block, then isolate the new fixture.
	await create_timer(0.08).timeout
	root.get_node("VizMP")._visualizer_host._active_visualizer._clear_history()
	await create_timer(0.27).timeout
	await RenderingServer.frame_post_draw

func _moments(image: Image) -> Vector4:
	var xx: float = 0.0
	var yy: float = 0.0
	var xy: float = 0.0
	var weight: float = 0.0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			var brightness: float = image.get_pixel(x, y).r
			if brightness < 0.005:
				continue
			var dx: float = float(x) / image.get_width() - 0.5
			var dy: float = float(y) / image.get_height() - 0.5
			xx += dx * dx * brightness
			yy += dy * dy * brightness
			xy += dx * dy * brightness
			weight += brightness
	return Vector4(xx / maxf(weight, 0.00001), yy / maxf(weight, 0.00001),
		xy / sqrt(maxf(xx * yy, 0.000000001)), weight)

func _trace_extent(image: Image) -> Vector2:
	var low := Vector2(image.get_width(), image.get_height())
	var high := Vector2.ZERO
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			if image.get_pixel(x, y).r > 0.03:
				low = low.min(Vector2(x, y))
				high = high.max(Vector2(x, y))
	return high - low

func _run() -> void:
	await process_frame
	_pcm = root.get_node("StereoPCM")
	_check(_pcm.consumer_count == 0, "PCM tap starts idle with no scope")
	var master: int = AudioServer.get_bus_index(&"Master")
	AudioServer.set_bus_mute(master, true)
	var main: Control = load("res://scenes/Main.tscn").instantiate()
	main.save_layout_enabled = false
	root.add_child(main)
	await process_frame
	main.set_visualizer_enabled(true, false)
	_player = main._player
	var host: Control = main._visualizer_host
	host.set_mode(host.Mode.SCOPE)
	var scope: Control = host._active_visualizer
	_check(_pcm.consumer_count == 1, "Selecting scope acquires one shared PCM consumer")
	_check(host._viewport.disable_3d, "Scope presentation disables unused 3D rendering")
	var texture_rid: RID = _pcm.pcm_texture.get_rid()
	var mesh_rid: RID = scope.beam.mesh.get_rid()
	await _play(_tone(0.0))
	_check(_pcm.peak > 0.1 and _pcm.texture_frame_count == 1024, "File capture fills the signed stereo PCM texture")
	_check(_pcm.correlation_valid and _pcm.correlation > 0.99, "In-phase stereo measures correlation +1")
	scope._gain = 24.0
	await process_frame
	await RenderingServer.frame_post_draw
	_check(scope._gain * _pcm.peak <= 0.96, "Common gain ceiling prevents first-frame transient clipping")
	var in_phase: Vector4 = _moments(scope.phosphor_viewport.get_texture().get_image())
	_check(in_phase.w > 1.0 and in_phase.z < -0.9, "GPU beam maps L to X and positive R upward")
	await _play(_tone(PI))
	_check(_pcm.correlation < -0.99, "Opposite-phase stereo measures correlation -1")
	var anti_phase: Vector4 = _moments(scope.phosphor_viewport.get_texture().get_image())
	_check(anti_phase.z > 0.9, "Opposite phase rotates the vector trace to the other diagonal")
	await _play(_tone(PI * 0.5))
	_check(absf(_pcm.correlation) < 0.05, "Quadrature stereo measures near-zero correlation")
	var circle: Vector4 = _moments(scope.phosphor_viewport.get_texture().get_image())
	_check(circle.w > 1.0 and absf(circle.z) < 0.1 and absf(circle.x / maxf(circle.y, 0.00001) - 1.0) < 0.1,
		"Quadrature PCM renders a circle in the accumulation buffer")
	await _play(_tone(PI * 0.5, 0.5))
	var ellipse: Vector2 = _trace_extent(scope.phosphor_viewport.get_texture().get_image())
	_check(absf(ellipse.y / maxf(ellipse.x, 0.00001) - 0.5) < 0.04,
		"Shared gain preserves the original L/R amplitude ratio")
	_check(_pcm.pcm_texture.get_rid() == texture_rid and scope.beam.mesh.get_rid() == mesh_rid,
		"PCM updates reuse texture and beam mesh resources")
	await _play(_tone(0.0, 0.0))
	_check(not _pcm.correlation_valid and _pcm.rms.y < 0.00001, "Single-channel audio reports undefined phase rather than a false correlation")
	# A 2:3 frequency ratio produces a classic multi-loop Lissajous preview.
	await _play(_tone(PI * 0.25, 1.0, 1.5))
	host._viewport.get_texture().get_image().save_png("res://.godot/oscilloscope-green.png")
	host.set_scope_palette(1)
	await RenderingServer.frame_post_draw
	host._viewport.get_texture().get_image().save_png("res://.godot/oscilloscope-amber.png")
	_check(scope._crt_material.get_shader_parameter(&"phosphor_color") == scope.PALETTES[1], "Amber palette applies without recreating the scope")
	_player.stop()
	await create_timer(0.1).timeout
	await RenderingServer.frame_post_draw
	var tail_start: Vector4 = _moments(scope.phosphor_viewport.get_texture().get_image())
	await create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	var tail_end: Vector4 = _moments(scope.phosphor_viewport.get_texture().get_image())
	_check(tail_start.w > 1.0 and tail_end.w > 0.01 and tail_end.w < tail_start.w * 0.5,
		"Actual retained framebuffer shows fading afterglow after playback stops")
	_check(_pcm.peak < 0.00003, "Silence blanks the live beam instead of drawing a bright center dot")
	_pcm.reset()
	await process_frame
	await RenderingServer.frame_post_draw
	var cleared: Vector4 = _moments(scope.phosphor_viewport.get_texture().get_image())
	_check(cleared.w < 0.1, "Track/source reset clears previous phosphor history")
	for preset in range(3):
		host.set_quality(preset)
		_check(scope.phosphor_viewport.size.x == scope.BUFFER_SIZES[preset], "Quality resizes bounded phosphor target: " + str(preset))
	var primitive_count: int = scope.beam.mesh.surface_get_array_index_len(0) / 3
	_check(primitive_count == 4094, "High preset keeps a bounded static ribbon of 4094 triangles")
	main._layout.detach_panel("visualizer")
	await process_frame
	_check(host._active_visualizer == scope and _pcm.consumer_count == 1, "Detachment retains the scope and a single PCM lease")
	main._layout.dock_panel("visualizer", 2)
	await process_frame
	var old_scope: WeakRef = weakref(scope)
	scope = null
	host.set_mode(host.Mode.RADIAL)
	await process_frame
	_check(old_scope.get_ref() == null and _pcm.consumer_count == 0, "Switching away releases scope resources and disables capture")
	for i in range(3):
		host.set_mode(host.Mode.SCOPE)
		host.set_mode(host.Mode.RADIAL)
	await process_frame
	_check(_pcm.consumer_count == 0 and host.get_child_count() == 1, "Repeated switching leaves no PCM leases or render targets behind")
	_player.stream = null
	_player = null
	main.queue_free()
	await create_timer(0.1).timeout
	AudioServer.set_bus_mute(master, false)
	print("Previews: ", ProjectSettings.globalize_path("res://.godot/oscilloscope-green.png"), " / oscilloscope-amber.png")
	print("Failures: ", _failures)
	quit(0 if _failures == 0 else 1)
