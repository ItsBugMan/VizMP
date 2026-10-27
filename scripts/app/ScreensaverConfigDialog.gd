extends ConfirmationDialog
## Shared modal for /c and Main Deck -> Settings. Preview changes are reversible.
var close_on_dismiss: bool = false
var _mode: OptionButton
var _quality: OptionButton
var _source: OptionButton
var _skin: OptionButton
var _directory: LineEdit
var _recursive: CheckBox
var _volume: HSlider
var _palette: OptionButton
var _error: Label
var _skin_paths: Array[String] = []
var _original_skin: String
var _finished: bool = false

func _ready() -> void:
	title = "VizMP Screensaver Settings"
	ok_button_text = "Save"
	dialog_hide_on_ok = false
	exclusive = true
	transient = true
	unresizable = true
	_original_skin = SkinManager.current_path
	SkinManager.register_root(self)
	var settings: Dictionary = ScreensaverManager.preferences
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	_mode = _option(column, "Default visualizer", preload("res://scripts/visualizers/VisualizerHost.gd").MODE_NAMES)
	_mode.select(settings.mode)
	_quality = _option(column, "Graphics quality", ["Low", "Balanced", "High"])
	_quality.select(settings.quality)
	_source = _option(column, "Audio source", ["Desktop loopback", "Shuffle playlist directory"])
	_source.select(0 if settings.audio_source == "desktop" else 1)
	_skin = _option(column, "Screensaver skin", [])
	for path in SkinManager.BUILTINS:
		_add_skin(path)
	var preferred_skin: String = SkinManager.REPLACEMENTS.get(settings.skin, settings.skin)
	_add_skin(preferred_skin)
	_add_skin(_original_skin)
	_skin.select(_skin_paths.find(preferred_skin))
	_skin.item_selected.connect(_preview_skin)
	var custom := Button.new()
	custom.text = "Choose custom skin…"
	custom.pressed.connect(_browse_skin)
	column.add_child(custom)
	_label(column, "Playlist directory (also used if desktop capture cannot start)")
	var row := HBoxContainer.new()
	column.add_child(row)
	_directory = LineEdit.new()
	_directory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_directory.text = settings.playlist_directory
	_directory.placeholder_text = "Choose a folder containing MP3, OGG or WAV files"
	row.add_child(_directory)
	var browse := Button.new()
	browse.text = "Browse…"
	browse.pressed.connect(_browse_directory)
	row.add_child(browse)
	_recursive = CheckBox.new()
	_recursive.text = "Include subfolders (directory links are skipped)"
	_recursive.button_pressed = settings.recursive
	column.add_child(_recursive)
	var volume_label: Label = _label(column, "Playlist playback: %.1f dB" % settings.volume_db)
	_volume = HSlider.new()
	_volume.min_value = -60.0
	_volume.max_value = 0.0
	_volume.step = 1.0
	_volume.value = settings.volume_db
	_volume.value_changed.connect(func(value: float) -> void: volume_label.text = "Playlist playback: %.1f dB" % value)
	column.add_child(_volume)
	_palette = _option(column, "Oscilloscope phosphor", ["Green", "Amber"])
	_palette.select(settings.scope_palette)
	var hint: Label = _label(column, "Preview embedding is unavailable. Windows' Preview button runs the full saver; the small thumbnail stays blank.")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 550
	_error = _label(column, "")
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.add_theme_color_override("font_color", Color(1.0, 0.55, 0.4))
	confirmed.connect(_save)
	canceled.connect(_cancel)
	close_requested.connect(_cancel)
	_preview_skin(_skin.selected)

func _input(event: InputEvent) -> void:
	# Handle Escape directly as well as AcceptDialog's action mapping. This
	# works in minimal /c startup and custom SceneTree harnesses alike.
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		set_input_as_handled()
		_cancel()

func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label

func _option(parent: Node, label: String, choices: Array) -> OptionButton:
	_label(parent, label)
	var option := OptionButton.new()
	for choice in choices:
		option.add_item(choice)
	parent.add_child(option)
	return option

func _add_skin(path: String) -> void:
	if path.is_empty() or path in _skin_paths:
		return
	_skin_paths.append(path)
	var name: String = path.get_file().get_basename()
	var file := FileAccess.open(path, FileAccess.READ)
	if file != null and file.get_length() <= 262144:
		var data: Variant = JSON.parse_string(file.get_as_text())
		if data is Dictionary and data.get("name") is String:
			name = data.name.left(80)
	_skin.add_item(name)

func _preview_skin(index: int) -> void:
	if index < 0 or index >= _skin_paths.size():
		return
	if SkinManager.load_skin(_skin_paths[index], false) != OK and _error != null:
		_error.text = SkinManager.last_error

func _browse_directory() -> void:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	if DirAccess.dir_exists_absolute(_directory.text):
		dialog.current_dir = _directory.text
	dialog.dir_selected.connect(func(path: String) -> void:
		_directory.text = path
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_clamped(Vector2i(850, 600), 0.85)

func _browse_skin() -> void:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.json ; VizMP skin"])
	dialog.file_selected.connect(func(path: String) -> void:
		if SkinManager.load_skin(path, false) == OK:
			_add_skin(path)
			_skin.select(_skin_paths.find(path))
			_error.text = ""
		else:
			_error.text = SkinManager.last_error
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_clamped(Vector2i(850, 600), 0.85)

func _save() -> void:
	var folder: String = _directory.text.strip_edges()
	if _source.selected == 1 and (not folder.is_absolute_path() or not DirAccess.dir_exists_absolute(folder)):
		_error.text = "Choose an existing absolute playlist directory."
		return
	if _skin.selected < 0 or SkinManager.load_skin(_skin_paths[_skin.selected], false) != OK:
		_error.text = "The selected skin could not be loaded."
		return
	var candidate: Dictionary = {
		"mode": _mode.selected, "quality": _quality.selected,
		"skin": _skin_paths[_skin.selected], "audio_source": "desktop" if _source.selected == 0 else "playlist",
		"playlist_directory": folder, "recursive": _recursive.button_pressed,
		"volume_db": _volume.value, "scope_palette": _palette.selected,
	}
	var error: Error = ScreensaverManager.save_preferences(candidate)
	if error != OK:
		_error.text = "Could not save screensaver settings: " + error_string(error)
		return
	_finish()

func _cancel() -> void:
	_finish()

func _finish() -> void:
	if _finished:
		return
	_finished = true
	SkinManager.load_skin(_original_skin, false)
	SkinManager.unregister_root(self)
	hide()
	if close_on_dismiss:
		ScreensaverManager.request_exit()
	queue_free()

func _exit_tree() -> void:
	SkinManager.unregister_root(self)
