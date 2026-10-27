extends Control
const AUDIO_LOADER = preload("res://scripts/audio/AudioStreamLoader.gd")
## Composition only: audio, visuals, docking and skins have separate owners.
const DOCK_LAYOUT = preload("res://scripts/ui/DockLayout.gd")
const EQUALIZER = preload("res://scripts/ui/EqualizerPanel.gd")
const PLAYLIST = preload("res://scripts/ui/PlaylistPanel.gd")
@export var save_layout_enabled: bool = true
@onready var _player: AudioStreamPlayer = $Player
@onready var _visualizer_host: Control = $Visualizer
var _transport: VBoxContainer
var _cover: TextureRect
var _immersive := false
var _visual_parent: Node
var _visual_index := 0
var _old_window_mode: int
var _old_borderless := false
var _visible_windows: Array[Window] = []
var _layout: MarginContainer
var _playlist: VBoxContainer
var _dialog: FileDialog
var _skin_dialog: FileDialog
var _status: Label
var _mode_button: Button
var _background: ColorRect
var _visual_mode: OptionButton
var _updates: AcceptDialog
var _update_status: Label
var _track_name: String = "Open or drop MP3, OGG, WAV or FLAC files."

func _ready() -> void:
	get_window().min_size = Vector2i(1000, 800)
	get_window().use_hdr_2d = true
	if DisplayServer.get_name() != "headless":
		get_window().hdr_output_requested = true
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
		window.files_dropped.connect(_on_files_dropped)
		window.window_input.connect(_input))
	_build_deck(_layout.add_panel("deck", "Main Deck"))
	var eq: VBoxContainer = EQUALIZER.new()
	_layout.add_panel("equalizer", "Equalizer").add_child(eq)
	eq.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_visualizer(_layout.add_panel("visualizer", "Visualizer"))
	_playlist = PLAYLIST.new()
	_layout.add_panel("playlist", "Playlist").add_child(_playlist)
	_playlist.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_playlist.track_requested.connect(_load_track)
	_transport.previous_requested.connect(_playlist.play_previous)
	_transport.next_requested.connect(_playlist.play_next)
	var library := preload("res://scripts/ui/LibraryPanel.gd").new()
	_layout.add_panel("library", "Library").add_child(library)
	library.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library.track_requested.connect(_load_track)
	library.queue_requested.connect(_playlist.add_paths)
	_player.finished.connect(_playlist.play_next)
	AudioLoopbackManager.register_file_player(_player)
	AudioLoopbackManager.status_changed.connect(_on_audio_status)
	AudioLoopbackManager.mode_changed.connect(_on_audio_mode)
	_dialog = FileDialog.new()
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_dialog.filters = PackedStringArray([AUDIO_LOADER.FILE_FILTER])
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
	_updates = preload("res://scripts/ui/UpdateDialog.gd").new()
	add_child(_updates)
	AutoUpdater.status_changed.connect(func(message: String) -> void: _update_status.text = message)
	_update_status.text = AutoUpdater.status
	AutoUpdater.restarting.connect(func() -> void: _layout.save_layout())

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
	_transport = preload("res://scripts/ui/TransportBar.gd").new()
	_transport.player = _player
	content.add_child(_transport)
	_cover = TextureRect.new()
	_cover.custom_minimum_size = Vector2(64, 64)
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cover.visible = false
	content.add_child(_cover)
	_mode_button = Button.new()
	_mode_button.text = "Live desktop audio"
	_mode_button.toggle_mode = true
	_mode_button.toggled.connect(_toggle_desktop)
	content.add_child(_mode_button)
	var settings := MenuButton.new()
	settings.text = "Settings / skin"
	content.add_child(settings)
	var menu: PopupMenu = settings.get_popup()
	for label in ["Classic Mint", "Midnight Violet", "Amber Terminal", "Cyberpunk", "Brushed Metal", "Retro Phosphor"]:
		menu.add_radio_check_item(label)
	menu.add_separator()
	menu.add_item("Load custom skin…", 100)
	menu.add_item("Reset panel layout", 101)
	menu.add_item("Screensaver settings…", 102)
	menu.add_item("Check for updates…", 103)
	menu.id_pressed.connect(func(id: int) -> void:
		if id < SkinManager.BUILTINS.size():
			_load_skin(SkinManager.BUILTINS[id])
		elif id == 100:
			_skin_dialog.popup_centered_ratio(0.7)
		elif id == 101:
			_layout.reset_layout()
		elif id == 102:
			ScreensaverManager.show_configuration()
		elif id == 103:
			_updates.popup_centered()
			AutoUpdater.check_for_updates())
	menu.about_to_popup.connect(func() -> void:
		for i in range(SkinManager.BUILTINS.size()):
			menu.set_item_checked(i, SkinManager.current_path == SkinManager.BUILTINS[i]))
	var hint := Label.new()
	hint.text = "Drag headers to swap panels. ↗ detaches.\nF11 fullscreen / Esc windowed"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(hint)
	_update_status = Label.new()
	_update_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_update_status)

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
	var fullscreen := Button.new()
	fullscreen.text = "Fullscreen · F11"
	fullscreen.pressed.connect(func() -> void: set_visualizer_fullscreen(true))
	controls.add_child(fullscreen)
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
	var stream: AudioStream = AUDIO_LOADER.load_file(path)
	if stream == null:
		_status.text = AUDIO_LOADER.last_error
		return
	AudioLoopbackManager.set_mode(AudioLoopbackManager.Mode.FILE)
	_player.stop()
	AudioAnalyzer.reset_after_seek()
	StereoPCM.reset()
	_player.stream = stream
	_player.stream_paused = false
	_player.play()
	var metadata := preload("res://scripts/audio/AudioMetadata.gd").read_track(path)
	_track_name = metadata.title
	if not metadata.artist.is_empty(): _track_name += "\n" + metadata.artist
	if not metadata.album.is_empty(): _track_name += " · " + metadata.album
	_cover.texture = metadata.cover
	_cover.visible = metadata.cover != null
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
	if not live:
		_status.text = _track_name

func _on_audio_status(message: String) -> void:
	_status.text = message

func _on_files_dropped(paths: PackedStringArray) -> void:
	_playlist.add_paths(paths)
	for path in paths:
		if AUDIO_LOADER.supports(path):
			_load_track(path)
			break

func _on_close() -> void:
	_layout.save_layout()
	get_tree().quit()

func _exit_tree() -> void:
	SkinManager.unregister_root(self)

func set_visualizer_fullscreen(enabled: bool) -> void:
	if _immersive == enabled: return
	_immersive = enabled
	if enabled:
		_layout.save_layout()
		_visual_parent = _visualizer_host.get_parent()
		_visual_index = _visualizer_host.get_index()
		_old_window_mode = get_window().mode
		_old_borderless = get_window().borderless
		_visible_windows.clear()
		for window: Window in _layout.windows.values():
			if window.visible:
				_visible_windows.append(window)
				window.hide()
		_visualizer_host.reparent(self, false)
		_visualizer_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_layout.hide()
		get_window().borderless = true
		get_window().mode = Window.MODE_FULLSCREEN
	else:
		get_window().mode = _old_window_mode
		get_window().borderless = _old_borderless
		_visualizer_host.reparent(_visual_parent, false)
		_visual_parent.move_child(_visualizer_host, _visual_index)
		_layout.show()
		for window in _visible_windows:
			if is_instance_valid(window): window.show()
		_visible_windows.clear()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			set_visualizer_fullscreen(not _immersive)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and _immersive:
			set_visualizer_fullscreen(false)
			get_viewport().set_input_as_handled()
	elif _immersive and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		set_visualizer_fullscreen(false)
		get_viewport().set_input_as_handled()
