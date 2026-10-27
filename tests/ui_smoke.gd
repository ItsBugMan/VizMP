extends SceneTree
## Real native-window and skin integration; no user settings are overwritten.
var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		_failures += 1
		push_error(label)

func _eq_count() -> int:
	var count: int = 0
	var bus: int = AudioServer.get_bus_index(&"Master")
	for i in range(AudioServer.get_bus_effect_count(bus)):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectEQ6:
			count += 1
	return count

func _run() -> void:
	await process_frame
	var skins: Node = root.get_node("SkinManager")
	var original_skin: String = skins.current_path
	var main: Control = load("res://scenes/Main.tscn").instantiate()
	main.save_layout_enabled = false
	root.add_child(main)
	await process_frame
	var layout: MarginContainer = main._layout
	main.set_visualizer_enabled(true, false)
	_check(layout.panels.size() == 5, "Five independent panels compose the split layout")
	_check(_eq_count() == 1, "File EQ is installed once")
	var fixture := AudioStreamWAV.new()
	fixture.mix_rate = 44100
	fixture.format = AudioStreamWAV.FORMAT_16_BITS
	var silence := PackedByteArray()
	silence.resize(8820)
	fixture.data = silence
	fixture.save_to_wav("res://.godot/ui-test-track.wav")
	var playlist: VBoxContainer = main._playlist
	playlist.add_paths(PackedStringArray(["res://.godot/ui-test-track.wav", "res://.godot/ui-test-track.wav", "res://README.md"]))
	_check(playlist.paths.size() == 1, "Playlist deduplicates tracks and ignores unsupported files")
	playlist._activate(0)
	_check(main._player.playing and playlist.current_index == 0, "Playlist activation loads and starts a real WAV stream")
	var eq: VBoxContainer = layout.panels.equalizer.content.get_child(0)
	eq._sliders[2].value = 4.5
	_check(is_equal_approx(eq._effect.get_band_gain_db(2), 4.5), "Equalizer slider changes the audio effect")
	for path in skins.BUILTINS:
		_check(skins.load_skin(path, false) == OK, "Skin loads: " + path.get_file())
	_check(main.theme == skins.active_theme, "Skin changes apply to the docked app")
	layout.dock_panel("equalizer", 3)
	_check(layout.order[3] == "equalizer" and layout.order[1] == "playlist", "Dock movement swaps occupants without losing a panel")
	_check(_eq_count() == 1 and is_equal_approx(eq._effect.get_band_gain_db(2), 4.5), "Dock movement preserves EQ resource and gain")
	layout._slots[0]._drop_data(Vector2.ZERO, {"vizmp_panel": "playlist"})
	_check(layout.order[0] == "playlist", "Panel drop requests route into the docking system")
	layout.detach_panel("equalizer")
	await process_frame
	var window: Window = layout.windows.equalizer
	_check(window.borderless and window.visible and not window.is_embedded(), "Undocked panel opens a real borderless OS window")
	_check(eq.get_window() == window and _eq_count() == 1, "Undocking preserves panel state and audio effect")
	skins.load_skin("res://skins/midnight-violet.json", false)
	_check(window.theme == skins.active_theme, "Live skin updates reach detached windows")
	layout.layout_path = "res://.godot/ui-test-layout.cfg"
	layout.persistence_enabled = true
	layout.save_layout()
	var saved_order: Array = layout.order.duplicate()
	var saved_config := ConfigFile.new()
	_check(saved_config.load(layout.layout_path) == OK and saved_config.has_section_key("windows", "equalizer"), "Layout records detached geometry")
	layout.persistence_enabled = false
	layout.reset_layout()
	await process_frame
	_check(layout.windows.is_empty() and layout.order == layout.DEFAULT_ORDER, "Reset restores all panels to their default docks")
	# Restore from a dedicated test copy; never touch the user's layout.cfg.
	layout.persistence_enabled = true
	layout.restore_layout()
	layout.persistence_enabled = false
	_check(layout.order == saved_order and layout.windows.has("equalizer"), "Saved panel order and detached state restore")
	layout.windows.equalizer.close_requested.emit()
	await process_frame
	_check(layout.windows.is_empty() and _eq_count() == 1, "Redocking closes the window without duplicate EQ effects")
	# Verify the atlas route with a procedural fixture, independent of imports.
	var bitmap := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	bitmap.fill(Color("#334455"))
	bitmap.fill_rect(Rect2i(4, 4, 16, 16), Color("#152535"))
	bitmap.save_png("res://.godot/ui-test-atlas.png")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://skins/classic-mint.json"))
	manifest.atlas = "ui-test-atlas.png"
	manifest.regions = {"panel": [0, 0, 24, 24], "button_normal": [0, 0, 24, 24]}
	manifest.margins = [4, 4, 4, 4]
	var file := FileAccess.open("res://.godot/ui-test-skin.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest))
	file.close()
	_check(skins.load_skin("res://.godot/ui-test-skin.json", false) == OK, "Custom atlas manifest loads")
	_check(skins.active_theme.get_stylebox("panel", "PanelContainer") is StyleBoxTexture, "Atlas uses a nine-slice StyleBoxTexture")
	var good_theme: Theme = skins.active_theme
	manifest.margins = [100, 4, 100, 4]
	file = FileAccess.open("res://.godot/ui-test-skin.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest))
	file.close()
	_check(skins.load_skin("res://.godot/ui-test-skin.json", false) != OK and skins.active_theme == good_theme, "Invalid atlas margins preserve the active skin")
	skins.load_skin("res://skins/classic-mint.json", false)
	main._visualizer_host.set_mode(1)
	main._visual_mode.select(1)
	var analyzer: Node = root.get_node("AudioAnalyzer")
	analyzer.set_process(false)
	analyzer.spectrum.fill(0.65)
	analyzer.bass = 0.6
	analyzer.sub_bass = 0.65
	analyzer.mid = 0.5
	analyzer.treble = 0.4
	analyzer.volume = 0.6
	analyzer.spectrum_updated.emit()
	await create_timer(0.6).timeout
	layout.detach_panel("visualizer")
	await create_timer(0.2).timeout
	_check(main._visualizer_host._viewport != null, "Particle viewport survives native-window detachment")
	layout.dock_panel("visualizer", 2)
	await create_timer(0.3).timeout
	layout.reset_layout()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/vizmp-ui-preview.png")
	print("Preview: ", ProjectSettings.globalize_path("res://.godot/vizmp-ui-preview.png"))
	skins.load_skin(original_skin, false)
	main.queue_free()
	await process_frame
	_check(_eq_count() == 0, "Destroying the UI removes its owned EQ")
	print("Failures: ", _failures)
	quit(0 if _failures == 0 else 1)
