extends Control
## Minimal runnable host. The future dock/theme system owns UI, while the
## visualizer and audio services remain independent of its layout.

@onready var _player: AudioStreamPlayer = $Player
var _dialog: FileDialog
var _status: Label

func _ready() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	var title := Label.new()
	title.text = "VIZMP  /  RADIAL LAB"
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)
	_status = Label.new()
	_status.text = "Open or drop an MP3, OGG or WAV to start.  /  F11 fullscreen"
	column.add_child(_status)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	var open := Button.new()
	open.text = " Open audio "
	open.pressed.connect(func() -> void: _dialog.popup_centered_ratio(0.7))
	buttons.add_child(open)
	var pause := Button.new()
	pause.text = " Pause / resume "
	pause.pressed.connect(func() -> void: _player.stream_paused = not _player.stream_paused)
	buttons.add_child(pause)
	_dialog = FileDialog.new()
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.filters = PackedStringArray(["*.mp3, *.ogg, *.wav ; Audio files"])
	_dialog.file_selected.connect(_load_track)
	add_child(_dialog)
	get_window().files_dropped.connect(_on_files_dropped)

func _load_track(path: String) -> void:
	# Runtime loaders support external files without importing into res://.
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
	_player.stop()
	AudioAnalyzer.reset_history()
	_player.stream = stream
	_player.stream_paused = false
	_player.play()
	_status.text = "PLAYING  /  " + path.get_file()

func _on_files_dropped(paths: PackedStringArray) -> void:
	if not paths.is_empty():
		_load_track(paths[0])

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			var full: bool = get_window().mode == Window.MODE_FULLSCREEN
			get_window().mode = Window.MODE_WINDOWED if full else Window.MODE_FULLSCREEN
		elif event.keycode == KEY_ESCAPE:
			get_window().mode = Window.MODE_WINDOWED
