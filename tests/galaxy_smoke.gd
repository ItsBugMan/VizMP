extends SceneTree
## Run with a real Forward+ renderer; --headless cannot validate GPU particles.
## Synthetic audio is injected only in this test; no sound is played.

var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error(label)

func _run() -> void:
	await process_frame
	var analyzer: Node = root.get_node("AudioAnalyzer")
	var publisher: Node = root.get_node("VisualizerShaderManager")
	analyzer.set_process(false)
	var main: Control = load("res://scenes/Main.tscn").instantiate()
	main.save_layout_enabled = false
	root.add_child(main)
	var host: Control = main._visualizer_host
	host.set_mode(1)
	await create_timer(1.0).timeout
	var galaxy: Node3D = host._active_visualizer
	_check(galaxy.particles.amount == 32768, "Balanced quality allocates 32768 GPU particles")
	_check(host._viewport.own_world_3d, "Galaxy has an isolated 3D world")
	_check(galaxy.particles.process_material.shader != null, "Custom particle process shader is assigned")
	var baseline_density: float = galaxy.particles.amount_ratio
	analyzer.spectrum.fill(0.7)
	analyzer.bass = 0.75
	analyzer.sub_bass = 0.8
	analyzer.mid = 0.6
	analyzer.treble = 0.4
	analyzer.volume = 0.65
	analyzer.spectrum_updated.emit()
	analyzer.beat_pulse = 1.0
	analyzer.beat_detected.emit(0.85)
	_check(galaxy.particles.amount_ratio > baseline_density, "Audio and transient increase emission density without reallocating particles")
	_check(publisher._beat_serial == 1, "Transient publishes a persistent GPU event serial")
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var image: Image = host._viewport.get_texture().get_image()
	_check(image != null and not image.is_empty(), "Forward+ renders a galaxy frame")
	var illuminated: int = 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var color: Color = image.get_pixel(x, y)
			if color.r + color.g + color.b > 0.2:
				illuminated += 1
	_check(illuminated > 100, "Rendered output contains visible particle geometry")
	var simulated_bounds: AABB = galaxy.particles.capture_aabb()
	_check(simulated_bounds.size.length() > 1.0, "GPU simulation produces nonempty particle bounds")
	_check(galaxy.particles.visibility_aabb.grow(0.5).encloses(simulated_bounds), "Visibility bounds contain the simulated burst positions")
	var image_path: String = "res://.godot/galaxy-preview.png"
	image.save_png(image_path)
	print("Preview: ", ProjectSettings.globalize_path(image_path))
	host.set_camera_motion(false)
	await create_timer(0.8).timeout
	var camera_pose: Transform3D = galaxy.camera.transform
	await create_timer(0.2).timeout
	_check(camera_pose.is_equal_approx(galaxy.camera.transform), "Disabling camera motion produces a stable camera")
	host.set_quality(0)
	_check(galaxy.particles.amount == 16384, "Low quality reduces particle allocation")
	host.set_quality(2)
	_check(galaxy.particles.amount == 65536, "High quality supports 65536 particles")
	var old_galaxy: WeakRef = weakref(galaxy)
	galaxy = null
	host.set_mode(0)
	await process_frame
	_check(old_galaxy.get_ref() == null, "Leaving galaxy releases scene and GPU owners")
	_check(host.get_node("Radial").visible, "Radial visualizer returns after galaxy deactivation")
	for i in range(3):
		host.set_mode(1)
		host.set_mode(0)
	await process_frame
	_check(host.get_child_count() == 1, "Repeated mode switches leave no viewport instances behind")
	main.queue_free()
	await process_frame
	print("Failures: ", _failures)
	quit(0 if _failures == 0 else 1)
