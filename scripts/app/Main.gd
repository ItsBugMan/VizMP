extends Control
## Composition only: audio, visuals, docking and skins have separate owners.
const DOCK_LAYOUT = preload("res://scripts/ui/DockLayout.gd")
const EQUALIZER = preload("res://scripts/ui/EqualizerPanel.gd")
const PLAYLIST = preload("res://scripts/ui/PlaylistPanel.gd")
@export var save_layout_enabled: bool = true
@onready var _player: AudioStreamPlayer = $Player
@onready var _visualizer_host: Control = $Visualizer
var _layout: MarginContainer
var _playlist: VBoxContainer
var _dialog: FileDialog
var _skin_dialog: FileDialog
var _status: Label
var _mode_button: Button
var _pause_button: Button
var _background: ColorRect
var _visual_mode: OptionButton
var _track_name: String = "Open or drop MP3, OGG or WAV files."

func _ready() -> void:
	get_window().min_size = Vector2i(820, 620)
	SkinManager.register_root(self)
	_background = ColorRect.new()
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.color = SkinManager.background_color
	add_child(_background)
	SkinManager.skin_changed.connect(func() -> void: _background.color = SkinManager.background_color)
	_layout = DOCK_LAYOUT.new()
	_layout.name = "DockLayout"
	_layout.persistence_enabled = save_layout_enabled
	add_child(_layout)
	_layout.panel_detached.connect(func(_id: String, window: Window) -> void:
		window.files_dropped.connect(_on_files_dropped))
	_build_deck(_layout.add_panel("deck", "Main Deck"))
	var eq: VBoxContainer = EQUALIZER.new()
	_layout.add_panel("equalizer", "Equalizer").add_child(eq)
	eq.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_visualizer(_layout.add_panel("visualizer", "Visualizer"))
	_playlist = PLAYLIST.new()
	_layout.add_panel("playlist", "Playlist").add_child(_playlist)
	_playlist.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_playlist.track_requested.connect(_load_track)
	_player.finished.connect(_playlist.play_next)
	AudioLoopbackManager.register_file_player(_player)
	AudioLoopbackManager.status_changed.connect(_on_audio_status)
	AudioLoopbackManager.mode_changed.connect(_on_audio_mode)
	_dialog = FileDialog.new()
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_dialog.filters = PackedStringArray(["*.mp3, *.ogg, *.wav ; Audio files"])
	_dialog.files_selected.connect(_on_files_dropped)
	add_child(_dialog)
	_skin_dialog = FileDialog.new()
	_skin_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_skin_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_skin_dialog.filters = PackedStringArray(["*.json ; VizMP skin"])
	_skin_dialog.file_selected.connect(_load_skin)
	add_child(_skin_dialog)
	get_window().files_dropped.connect(_on_files_dropped)
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(_on_close)
	_layout.restore_layout.call_deferred()

func _build_deck(content: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "VIZMP"
	title.add_theme_font_size_override("font_size", 28)
	content.add_child(title)
	_status = Label.new()
	_status.text = _track_name
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(240, 55)
	content.add_child(_status)
	var buttons := HBoxContainer.new()
	content.add_child(buttons)
	var open := Button.new()
	open.text = "Open audio"
	open.pressed.connect(func() -> void: _dialog.popup_centered_ratio(0.7))
	buttons.add_child(open)
	_pause_button = Button.new()
	_pause_button.text = "Pause / resume"
	_pause_button.pressed.connect(func() -> void: _player.stream_paused = not _player.stream_paused)
	buttons.add_child(_pause_button)
	_mode_button = Button.new()
	_mode_button.text = "Live desktop audio"
	_mode_button.toggle_mode = true
	_mode_button.toggled.connect(_toggle_desktop)
	content.add_child(_mode_button)
	var settings := MenuButton.new()
	settings.text = "Settings / skin"
	content.add_child(settings)
	var menu: PopupMenu = settings.get_popup()
	for label in ["Classic Mint", "Midnight Violet", "Amber Terminal"]:
		menu.add_radio_check_item(label)
	menu.add_separator()
	menu.add_item("Load custom skin…", 100)
	menu.add_item("Reset panel layout", 101)
	menu.add_item("Screensaver settings…", 102)
	menu.id_pressed.connect(func(id: int) -> void:
		if id < 3:
			_load_skin(SkinManager.BUILTINS[id])
		elif id == 100:
			_skin_dialog.popup_centered_ratio(0.7)
		elif id == 101:
			_layout.reset_layout()
		elif id == 102:
			ScreensaverManager.show_configuration())
	menu.about_to_popup.connect(func() -> void:
		for i in range(3):
			menu.set_item_checked(i, SkinManager.current_path == SkinManager.BUILTINS[i]))
	var hint := Label.new()
	hint.text = "Drag headers to swap panels. ↗ detaches.\nF11 fullscreen / Esc windowed"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(hint)

func _build_visualizer(content: VBoxContainer) -> void:
	var controls := HFlowContainer.new()
	content.add_child(controls)
	var mode := OptionButton.new()
	_visual_mode = mode
	mode.add_item("Radial spectrum")
	mode.add_item("Particle galaxy")
	mode.add_item("Fractal tunnel")
	mode.add_item("Spectrum city")
	mode.add_item("Vector CRT scope")
	mode.item_selected.connect(_visualizer_host.set_mode)
	_visualizer_host.mode_changed.connect(func(selected: int) -> void: mode.select(selected))
	controls.add_child(mode)
	var quality := OptionButton.new()
	for label in ["Low", "Balanced", "High"]:
		quality.add_item(label)
	quality.select(1)
	quality.item_selected.connect(_visualizer_host.set_quality)
	controls.add_child(quality)
	var motion := CheckButton.new()
	motion.text = "Camera motion"
	motion.button_pressed = true
	motion.toggled.connect(_visualizer_host.set_camera_motion)
	controls.add_child(motion)
	var palette := OptionButton.new()
	palette.add_item("Green phosphor")
	palette.add_item("Amber phosphor")
	palette.visible = false
	palette.item_selected.connect(_visualizer_host.set_scope_palette)
	_visualizer_host.scope_palette_changed.connect(func(selected: int) -> void: palette.select(selected))
	controls.add_child(palette)
	_visualizer_host.mode_changed.connect(func(selected: int) -> void:
		palette.visible = selected == _visualizer_host.Mode.SCOPE
		motion.disabled = selected == _visualizer_host.Mode.SCOPE)
	_visualizer_host.reparent(content, false)
	_visualizer_host.custom_minimum_size = Vector2(320, 200)
	_visualizer_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_visualizer_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _load_track(path: String) -> void:
	var stream: AudioStream
	match path.get_extension().to_lower():
		"mp3": stream = AudioStreamMP3.load_from_file(path)
		"ogg": stream = AudioStreamOggVorbis.load_from_file(path)
		"wav": stream = AudioStreamWAV.load_from_file(path)
		_:
			_status.text = "Choose an MP3, OGG or WAV file."
			return
	if stream == null:
		_status.text = "Could not read: " + path.get_file()
		return
	AudioLoopbackManager.set_mode(AudioLoopbackManager.Mode.FILE)
	_player.stop()
	AudioAnalyzer.reset_history()
	StereoPCM.reset()
	_player.stream = stream
	_player.stream_paused = false
	_player.play()
	_track_name = "PLAYING / " + path.get_file()
	_status.text = _track_name
	_playlist.add_paths(PackedStringArray([path]))
	_playlist.mark_playing(path)

func _load_skin(path: String) -> void:
	if SkinManager.load_skin(path) != OK:
		_status.text = "Skin: " + SkinManager.last_error

func _toggle_desktop(enabled: bool) -> void:
	var next: AudioLoopbackManager.Mode = AudioLoopbackManager.Mode.DESKTOP if enabled else AudioLoopbackManager.Mode.FILE
	if AudioLoopbackManager.set_mode(next) != OK:
		_mode_button.set_pressed_no_signal(false)

func _on_audio_mode(next: int) -> void:
	var live: bool = next == AudioLoopbackManager.Mode.DESKTOP
	_mode_button.set_pressed_no_signal(live)
	_pause_button.disabled = live
	if not live:
		_status.text = _track_name

func _on_audio_status(message: String) -> void:
	_status.text = message

func _on_files_dropped(paths: PackedStringArray) -> void:
	_playlist.add_paths(paths)
	for path in paths:
		if path.get_extension().to_lower() in ["mp3", "ogg", "wav"]:
			_load_track(path)
			break

func _on_close() -> void:
	_layout.save_layout()
	get_tree().quit()

func _exit_tree() -> void:
	SkinManager.unregister_root(self)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			var full: bool = get_window().mode == Window.MODE_FULLSCREEN
			get_window().mode = Window.MODE_WINDOWED if full else Window.MODE_FULLSCREEN
		elif event.keycode == KEY_ESCAPE:
			get_window().mode = Window.MODE_WINDOWED
