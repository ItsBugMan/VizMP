extends SceneTree
## Real Forward+ pixels, silence, bounded bolts, skins and viewport lifecycle.
## Only .godot fixtures are written; existing user preferences are preserved.
var failures: int = 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	print("PASS: " if ok else "FAIL: ", message)
	if not ok: failures += 1

func pixels(image: Image, exact: bool = false) -> int:
	var count: int = 0
	for y in range(0, image.get_height(), 1 if exact else 3):
		for x in range(0, image.get_width(), 1 if exact else 3):
			var c: Color = image.get_pixel(x, y)
			if c.r > 0.0 or c.g > 0.0 or c.b > 0.0: count += 1
	return count

func profile(host: Control, label: String) -> void:
	host._container.stretch = false
	host._viewport.size = Vector2i(1920, 1080)
	var rid: RID = host._viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	for i in range(12): await RenderingServer.frame_post_draw
	var samples: Array[float] = []
	for i in range(24):
		await RenderingServer.frame_post_draw
		var ms: float = RenderingServer.viewport_get_measured_render_time_gpu(rid)
		if ms > 0.0: samples.append(ms)
	if not samples.is_empty():
		samples.sort()
		print("GPU / ", label, " / 1920x1080 / median ", snappedf(samples[samples.size() / 2], 0.001), " ms (viewport only)")
	RenderingServer.viewport_set_measure_render_time(rid, false)
	var preview: Image = host._viewport.get_texture().get_image()
	preview.convert(Image.FORMAT_RGB8)
	preview.linear_to_srgb()
	preview.save_png("res://.godot/" + label + "-1080p.png")
	host._container.stretch = true

func run() -> void:
	await process_frame
	var analyzer: Node = root.get_node("AudioAnalyzer")
	var skins: Node = root.get_node("SkinManager")
	var original_skin: String = skins.current_path
	analyzer.set_process(false)
	var normal: float = analyzer._display_energy(0.01)
	analyzer.sensitivity = 2.0
	check(analyzer._display_energy(0.01) > normal, "Sensitivity scales normalized energy")
	check(analyzer._display_energy(0.0) == 0.0, "Sensitivity preserves exact silence")
	analyzer.sensitivity = -3.0
	check(analyzer.sensitivity == 0.0, "Sensitivity cannot become negative")
	analyzer.sensitivity = 1.0
	var smooth_a: float = analyzer._smooth(0.0, 1.0, 1.0 / 30.0)
	var smooth_b: float = analyzer._smooth(analyzer._smooth(0.0, 1.0, 1.0 / 60.0), 1.0, 1.0 / 60.0)
	check(is_equal_approx(smooth_a, smooth_b), "Exponential smoothing is invariant to frame subdivision")
	var main: Control = load("res://scenes/Main.tscn").instantiate()
	main.save_layout_enabled = false
	root.add_child(main)
	await process_frame
	var host: Control = main._visualizer_host
	check(not main.visualizer_enabled and not host.visible and not main._layout.panels.visualizer.visible, "Deck opens with visualizer minimized")
	main.set_visualizer_fullscreen(true)
	check(host.visible and host.get_parent() == main, "F11 can open a minimized visualizer")
	main.set_visualizer_fullscreen(false)
	check(not host.visible and not main.visualizer_enabled, "Fullscreen exit restores minimized state")
	main._show_visual_settings()
	check(main._viewport_toggle.text == "Enable Visualizer Viewport", "Settings exposes the requested viewport checkbox")
	main._viewport_toggle.button_pressed = true
	main._visual_settings.hide()
	check(main.visualizer_enabled and host.visible, "Settings checkbox restores rendering")
	for path in skins.BUILTINS:
		check(skins.load_skin(path, false) == OK, "Skin validates: " + path.get_file())
	main._layout.detach_panel("equalizer")
	await process_frame
	var window: Window = main._layout.windows.equalizer
	check(window.transparent and window.transparent_bg and window.theme == skins.active_theme, "Shaped floating panels retain their skin")
	main._layout.dock_panel("equalizer", 1)
	host.set_mode(host.Mode.LIGHTNING)
	await create_timer(0.15).timeout
	var storm: Control = host._active_visualizer
	analyzer.mid = 0.0
	analyzer.treble = 0.0
	storm.strike(1.0)
	var quiet_forks: int = storm._paths.size()
	analyzer.mid = 1.0
	analyzer.treble = 1.0
	for quality in range(3):
		host.set_quality(quality)
		storm.strike(1.0)
		check(storm._segments <= storm.SEGMENT_LIMIT, "Lightning geometry stays bounded at quality %d" % quality)
	check(storm._paths.size() > quiet_forks, "Mid and treble increase fork density")
	storm.set_process(false)
	storm._age = 0.04
	storm._clouds.set_shader_parameter(&"flash", 0.75)
	storm.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = host._viewport.get_texture().get_image()
	check(pixels(image) > 200, "Lightning and cloud illumination reach actual GPU pixels")
	image.save_png("res://.godot/lightning-preview.png")
	await profile(host, "lightning")
	storm._age = 10.0
	storm.queue_redraw()
	await RenderingServer.frame_post_draw
	host._viewport.get_texture().get_image().save_png("res://.godot/clouds-preview.png")
	main.set_visualizer_enabled(false)
	check(host._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and storm.process_mode == Node.PROCESS_MODE_DISABLED, "Hidden viewport stops rendering and mode processing")
	main.set_visualizer_enabled(true)
	host.set_mode(host.Mode.ASCII_RAIN)
	await create_timer(0.2).timeout
	var rain: Control = host._active_visualizer
	analyzer.signal_active = true
	analyzer.volume = 0.9
	analyzer.spectrum.fill(0.85)
	analyzer.spectrum_updated.emit()
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	image = host._viewport.get_texture().get_image()
	check(pixels(image) > 200, "Active ASCII glyphs reveal the portrait")
	image.save_png("res://.godot/ascii-preview.png")
	await profile(host, "ascii-rain")
	main._layout.detach_panel("visualizer")
	main.set_visualizer_enabled(false)
	check(not main._layout.windows.visualizer.visible, "Disabling hides a detached visualizer window")
	main.set_visualizer_enabled(true)
	check(main._layout.windows.visualizer.visible and host._active_visualizer == rain, "Restoring preserves detached visualizer ownership")
	main._layout.dock_panel("visualizer", 2)
	# Zero raw activity must clear pixels even while smoothed energy remains high.
	analyzer.signal_active = false
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	image = host._viewport.get_texture().get_image()
	check(pixels(image, true) == 0, "Silence produces exactly zero visible RGB pixels")
	image.save_png("res://.godot/ascii-silence.png")
	var previous: WeakRef = weakref(rain)
	rain = null
	host.set_mode(host.Mode.TUNNEL)
	await process_frame
	check(previous.get_ref() == null, "Mode switch releases rain and glyph atlas")
	var tunnel: Control = host._active_visualizer
	tunnel.set_process(false)
	analyzer.sub_bass = 0.0
	tunnel._process(1.0)
	var speed: float = tunnel._speed
	analyzer.sub_bass = 1.0
	tunnel._process(1.0)
	check(absf(tunnel._speed - speed) < 0.05, "Bass cannot displace the tunnel camera")
	main.set_visualizer_enabled(false)
	host.set_mode(host.Mode.SCOPE)
	check(host._active_visualizer.phosphor_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Hidden scope suspends its nested phosphor viewport")
	check(root.get_node("StereoPCM").consumer_count == 0, "Hidden scope releases its PCM capture lease")
	for mode in range(7): host.set_mode(mode)
	check(host._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Mode switching cannot reactivate a hidden viewport")
	main.set_visualizer_enabled(true)
	await create_timer(0.1).timeout
	check(host._active_visualizer._atlas.render_target_update_mode == SubViewport.UPDATE_ONCE, "Restored glyph atlas retains its one-shot update mode")
	skins.load_skin("res://skins/neon-ronin.json", false)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/expansion-ui-preview.png")
	skins.load_skin(original_skin, false)
	main.queue_free()
	await process_frame
	print("Failures: ", failures)
	quit(0 if failures == 0 else 1)
