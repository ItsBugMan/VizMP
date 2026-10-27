extends SceneTree
## Real Forward+/D3D12 rendering. Injects test audio; does not play sound.
var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error(label)

func _difference(a: Image, b: Image) -> float:
	if a.get_size() != b.get_size():
		return 1.0
	var total: float = 0.0
	var samples: int = 0
	for y in range(0, a.get_height(), 4):
		for x in range(0, a.get_width(), 4):
			var left: Color = a.get_pixel(x, y)
			var right: Color = b.get_pixel(x, y)
			total += absf(left.r - right.r) + absf(left.g - right.g) + absf(left.b - right.b)
			samples += 1
	return total / maxi(samples, 1)

func _visible_pixels(image: Image) -> int:
	var count: int = 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.r + pixel.g + pixel.b > 0.25:
				count += 1
	return count

func _frame(viewport: SubViewport) -> Image:
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func _profile(viewport: SubViewport, label: String) -> void:
	var viewport_rid: RID = viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	for i in range(8):
		await RenderingServer.frame_post_draw
	var times: Array[float] = []
	for i in range(24):
		await RenderingServer.frame_post_draw
		var value: float = RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)
		if value > 0.0:
			times.append(value)
	if not times.is_empty():
		times.sort()
		print("GPU sample / ", label, " / viewport ", viewport.size, " / 3D scale ", viewport.scaling_3d_scale,
			" / median ", snappedf(times[times.size() / 2], 0.001), " ms (viewport only)")
	RenderingServer.viewport_set_measure_render_time(viewport_rid, false)

func _run() -> void:
	await process_frame
	var analyzer: Node = root.get_node("AudioAnalyzer")
	analyzer.set_process(false)
	var main: Control = load("res://scenes/Main.tscn").instantiate()
	main.save_layout_enabled = false
	root.add_child(main)
	var host: Control = main._visualizer_host
	host.set_mode(host.Mode.TUNNEL)
	await create_timer(0.3).timeout
	var tunnel: Control = host._active_visualizer
	_check(main._visual_mode.selected == host.Mode.TUNNEL, "Visualizer selector stays in sync with the host")
	_check(host._container.stretch_shrink == 2, "Balanced tunnel renders at half resolution in both axes")
	_check(host._viewport.disable_3d, "Tunnel viewport disables unused 3D rendering")
	var distance_before: float = tunnel.flight_distance
	await create_timer(0.1).timeout
	var quiet_distance: float = tunnel.flight_distance - distance_before
	analyzer.sub_bass = 1.0
	await create_timer(0.6).timeout
	distance_before = tunnel.flight_distance
	await create_timer(0.1).timeout
	_check(tunnel.flight_distance - distance_before > quiet_distance * 3.0, "Sub-bass increases integrated flight speed")
	host.set_camera_motion(false)
	distance_before = tunnel.flight_distance
	await create_timer(0.1).timeout
	_check(is_equal_approx(tunnel.flight_distance, distance_before), "Motion switch freezes tunnel flight")
	var tunnel_quiet: Image = await _frame(host._viewport)
	_check(_visible_pixels(tunnel_quiet) > 100, "Raymarch shader renders visible corridor geometry")
	analyzer.mid = 0.9
	analyzer.treble = 0.8
	analyzer.highs = 0.7
	analyzer.beat_pulse = 0.9
	await create_timer(0.1).timeout
	var tunnel_loud: Image = await _frame(host._viewport)
	_check(_difference(tunnel_quiet, tunnel_loud) > 0.005, "Mid/treble/transient inputs change the rendered tunnel")
	tunnel_loud.save_png("res://.godot/tunnel-preview.png")
	await _profile(host._viewport, "tunnel balanced")
	for preset in range(3):
		host.set_quality(preset)
		_check(tunnel._material.get_shader_parameter(&"march_steps") == tunnel.STEP_BUDGETS[preset], "Tunnel quality bounds ray steps: " + str(preset))
	analyzer.mid = 1.0
	await create_timer(0.1).timeout
	var high_tunnel: Image = await _frame(host._viewport)
	_check(high_tunnel.get_width() > tunnel_loud.get_width(), "High tunnel quality renders at the panel's full resolution")
	high_tunnel.save_png("res://.godot/tunnel-preview.png")
	main._layout.detach_panel("visualizer")
	await create_timer(0.1).timeout
	_check(host._active_visualizer == tunnel, "Detached viewport retains the same tunnel instance")
	main._layout.dock_panel("visualizer", 2)
	host.set_quality(1)
	var old_tunnel: WeakRef = weakref(tunnel)
	tunnel = null
	host.set_mode(host.Mode.CITY)
	await create_timer(0.3).timeout
	_check(old_tunnel.get_ref() == null, "Switching to city releases the tunnel scene")
	var city: Node3D = host._active_visualizer
	var multimesh: MultiMesh = city.buildings.multimesh
	_check(multimesh.instance_count == 784 and multimesh.use_custom_data, "Balanced city batches 784 buildings with custom instance data")
	var bins: Dictionary = {}
	for i in range(multimesh.instance_count):
		bins[int(floor(multimesh.get_instance_custom_data(i).r * 64.0))] = true
	_check(bins.size() == 64, "Building mapping covers all 64 frequency bins")
	_check(multimesh.custom_aabb.end.y >= city.MAX_HEIGHT, "Culling bounds include maximum shader-displaced height")
	analyzer.bass = 0.0
	analyzer.sub_bass = 0.0
	analyzer.beat_pulse = 0.0
	analyzer.spectrum.fill(0.0)
	analyzer.spectrum_updated.emit()
	await create_timer(0.1).timeout
	var low_city: Image = await _frame(host._viewport)
	var static_buffer: PackedFloat32Array = multimesh.buffer
	analyzer.spectrum.fill(1.0)
	analyzer.spectrum_updated.emit()
	await create_timer(0.1).timeout
	var high_city: Image = await _frame(host._viewport)
	_check(_visible_pixels(high_city) > 100, "Forward+ renders opaque buildings and luminous windows")
	_check(_difference(low_city, high_city) > 0.005, "Spectrum changes GPU-rendered building heights and windows")
	_check(static_buffer == multimesh.buffer, "Spectrum animation leaves CPU instance transforms unchanged")
	# Leave the streets visible: maximum-height towers occlude inner floor rings.
	for i in range(64):
		analyzer.spectrum[i] = 0.18 + pow(0.5 + 0.5 * sin(i * 0.36), 3.0) * 0.62
	analyzer.spectrum_updated.emit()
	await create_timer(0.1).timeout
	var before_wave: Image = await _frame(host._viewport)
	analyzer.beat_detected.emit(0.9)
	_check(city._waves[0].w > 0.8, "Transient listener creates a floor shockwave")
	await create_timer(0.4).timeout
	_check(city._waves[0].z > 0.35, "Floor shockwave propagates with elapsed time")
	var wave_city: Image = await _frame(host._viewport)
	_check(_difference(before_wave, wave_city) > 0.0001, "Shockwave reaches the rendered floor")
	wave_city.save_png("res://.godot/city-preview.png")
	await _profile(host._viewport, "city balanced")
	var camera: Camera3D = city.camera
	var resting_distance: float = camera.position.length()
	host.set_camera_motion(true)
	analyzer.bass = 1.0
	analyzer.sub_bass = 1.0
	analyzer.beat_detected.emit(1.0)
	await create_timer(1.0).timeout
	_check(camera.position.length() < resting_distance * 0.92, "Heavy bass brings the orbital camera closer")
	host.set_camera_motion(false)
	var frozen: Transform3D = camera.transform
	await create_timer(0.1).timeout
	_check(frozen.is_equal_approx(camera.transform), "Camera motion switch holds city camera steady")
	for i in range(20):
		analyzer.beat_detected.emit(0.8)
	_check(city._waves.size() == 8 and city._next_wave < 8, "Repeated beats reuse a bounded eight-wave pool")
	host.set_quality(0)
	_check(city.buildings.multimesh.instance_count == 441, "Low city quality uses 441 buildings")
	host.set_quality(2)
	_check(city.buildings.multimesh.instance_count == 1764, "High city quality uses 1764 buildings")
	main._layout.detach_panel("visualizer")
	await create_timer(0.2).timeout
	_check(host._active_visualizer == city, "Detached viewport retains the same city instance")
	main._layout.dock_panel("visualizer", 2)
	await process_frame
	var old_city: WeakRef = weakref(city)
	camera = null
	city = null
	multimesh = null
	host.set_mode(host.Mode.RADIAL)
	await process_frame
	_check(old_city.get_ref() == null, "Leaving city releases its scene and GPU owners")
	for selected in [2, 3, 2, 0, 3, 0]:
		host.set_mode(selected)
	await process_frame
	_check(host.get_child_count() == 1, "Repeated switching leaves only the radial child")
	main.queue_free()
	await process_frame
	print("Previews: ", ProjectSettings.globalize_path("res://.godot/tunnel-preview.png"), " / ", ProjectSettings.globalize_path("res://.godot/city-preview.png"))
	print("Failures: ", _failures)
	quit(0 if _failures == 0 else 1)
