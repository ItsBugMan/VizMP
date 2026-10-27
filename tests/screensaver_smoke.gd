extends SceneTree
## Parser, config, input guards, native configuration modal and isolated saver.
## Writes only .godot test fixtures; never overwrites the user's saver config.
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
	var manager: Node = root.get_node("ScreensaverManager")
	var original_preferences: Dictionary = manager.preferences.duplicate()
	var original_path: String = manager.config_path
	var original_skin: String = root.get_node("SkinManager").current_path
	var cases: Array = [
		[[], false, manager.LaunchMode.APP], [[], true, manager.LaunchMode.SAVER],
		[["/S"], false, manager.LaunchMode.SAVER], [["/c:123456"], false, manager.LaunchMode.CONFIG],
		[["/c", "123456"], false, manager.LaunchMode.CONFIG], [["/p", "123456"], false, manager.LaunchMode.PREVIEW],
		[["/P:0x1234"], false, manager.LaunchMode.PREVIEW], [["/p"], false, manager.LaunchMode.PREVIEW],
		[["/p", "bad", "/s"], true, manager.LaunchMode.PREVIEW], [["/c", "/s"], false, manager.LaunchMode.INVALID],
		[["/unknown"], true, manager.LaunchMode.INVALID], [["/s", "/s"], false, manager.LaunchMode.SAVER],
		[["--path", "D:/Godot Engine/Apps/VizMP/viz-mp", "--quit-after", "2", "/s"], false, manager.LaunchMode.SAVER],
	]
	for row in cases:
		var parsed: Dictionary = manager.parse_arguments(PackedStringArray(row[0]), row[1])
		_check(parsed.mode == row[2], "Argument dispatch: " + str(row[0]))
	_check(not manager.parse_arguments(PackedStringArray(["/p:0"])).handle_valid, "Zero preview HWND is rejected without a fullscreen fallback")
	_check(manager.parse_arguments(PackedStringArray(["/p", "1234567890123"])).handle == "1234567890123", "64-bit HWND text is preserved without float truncation")
	manager.begin_session(false)
	manager.set_process(false)
	manager.set_process_input(false)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100, 100)
	_check(not manager.should_exit_on_input(motion), "Startup grace ignores initial mouse warp")
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	_check(not manager.should_exit_on_input(key), "Startup grace ignores activation key")
	manager._process(0.6)
	motion.relative = Vector2(1, 0)
	_check(not manager.should_exit_on_input(motion), "Small mouse jitter does not exit")
	motion.relative = Vector2(-1, 0)
	for i in range(20):
		manager.should_exit_on_input(motion)
		motion.relative *= -1
	_check(manager._motion.length() < 2.0, "Alternating jitter cancels rather than accumulating distance")
	motion.relative = Vector2(9, 0)
	_check(manager.should_exit_on_input(motion), "Intentional movement exceeds tolerance")
	_check(manager.should_exit_on_input(key), "Keyboard press exits after grace")
	key.pressed = false
	_check(not manager.should_exit_on_input(key), "Key release does not trigger exit")
	manager._process(2.1)
	_check(Input.mouse_mode == Input.MOUSE_MODE_HIDDEN, "Cursor hides after two idle seconds")
	manager.end_session()
	_check(not manager.session_active, "Ending a session disarms the exit guard")
	manager.config_path = "res://.godot/screensaver-test.cfg"
	var settings: Dictionary = manager.DEFAULTS.duplicate()
	settings.mode = 4
	settings.quality = 0
	settings.skin = "res://skins/amber-terminal.json"
	settings.audio_source = "playlist"
	settings.playlist_directory = ProjectSettings.globalize_path("res://.godot/screensaver-fixtures")
	DirAccess.make_dir_recursive_absolute(settings.playlist_directory.path_join("album"))
	_check(manager.save_preferences(settings) == OK, "Screensaver preferences save atomically")
	settings.mode = 2
	_check(manager.save_preferences(settings) == OK, "Existing screensaver config can be replaced on Windows")
	manager.preferences = manager.DEFAULTS.duplicate()
	manager.load_preferences()
	_check(manager.preferences.mode == 2 and manager.preferences.audio_source == "playlist", "Mode and audio preferences persist")
	_check(manager.preferences.skin == settings.skin and manager.preferences.playlist_directory == settings.playlist_directory, "Skin and playlist directory persist")
	var invalid: Dictionary = manager.normalized_preferences({"mode": 999, "quality": "bad", "audio_source": "bad"})
	_check(invalid.mode == 6 and invalid.quality == 1 and invalid.audio_source == "desktop", "Malformed preference fields normalize safely")
	# Test the actual modal; opening/canceling must not modify saved preferences.
	manager.show_configuration(false)
	await process_frame
	var dialog: Window = manager._configuration
	_check(dialog.visible and dialog.exclusive, "Configuration opens an exclusive native modal")
	await RenderingServer.frame_post_draw
	dialog.get_texture().get_image().save_png("res://.godot/screensaver-settings-preview.png")
	dialog._mode.select(3)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	dialog.push_input(escape)
	await process_frame
	_check(not is_instance_valid(dialog) and manager.preferences.mode == 2 and root.get_node("SkinManager").current_path == original_skin, "Escape cancels the modal, restores the prior skin and leaves preferences untouched")
	manager.show_configuration(false)
	await process_frame
	dialog = manager._configuration
	dialog._mode.select(0)
	dialog._save()
	await process_frame
	_check(manager.preferences.mode == 0, "Configuration Save writes the selected mode")
	# Real decodable WAV fixtures; Master is muted after the analysis/capture taps.
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 44100
	var bytes := PackedByteArray()
	bytes.resize(44100 * 2)
	wav.data = bytes
	wav.save_to_wav(settings.playlist_directory.path_join("one.wav"))
	wav.save_to_wav(settings.playlist_directory.path_join("album/two.wav"))
	var ignored := FileAccess.open(settings.playlist_directory.path_join("ignore.txt"), FileAccess.WRITE)
	ignored.store_string("Not audio")
	ignored.close()
	manager.preferences = manager.DEFAULTS.duplicate()
	manager.preferences.mode = 0
	var saver: Control = load("res://scenes/Screensaver.tscn").instantiate()
	saver.configure_display = false
	saver.start_audio = false
	root.add_child(saver)
	manager.set_process_input(false)
	_check(saver.get_node_or_null("DockLayout") == null and saver.get_node_or_null("Visualizer") != null, "Saver creates a visualizer without modular UI or saved docks")
	var shallow: Array = await saver.scan_directory(settings.playlist_directory, false)
	var recursive: Array = await saver.scan_directory(settings.playlist_directory, true)
	_check(shallow.size() == 1 and recursive.size() == 2, "Cooperative playlist scan respects recursion and file types")
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Master"), true)
	saver.playlist.assign(recursive)
	saver.playlist.shuffle()
	saver._play_next()
	await create_timer(0.1).timeout
	_check(saver.player.playing, "Screensaver playlist starts actual WAV playback")
	saver.player.stop()
	saver.queue_free()
	await create_timer(0.1).timeout
	_check(not manager.session_active, "Saver cleanup restores the cursor and input state")
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Master"), false)
	manager.config_path = original_path
	manager.preferences = original_preferences
	root.get_node("SkinManager").load_skin(original_skin, false)
	print("Failures: ", _failures)
	quit(0 if _failures == 0 else 1)
