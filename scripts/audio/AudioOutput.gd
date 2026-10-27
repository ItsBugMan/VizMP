extends Node
## Persistent Master gain. DesktopAnalysis and its silent sink are never changed.
signal changed
const SETTINGS_PATH: String = "user://settings.cfg"
const SILENCE_DB: float = -80.0
const SAVE_DELAY: float = 0.2
var settings_path: String = SETTINGS_PATH
var volume_linear: float = 1.0
var muted: bool = false
var _save_timer: Timer
var _dirty: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY
	_save_timer.timeout.connect(save_settings)
	add_child(_save_timer)
	load_settings()

func load_settings() -> void:
	var bus: int = AudioServer.get_bus_index(&"Master")
	volume_linear = clampf(db_to_linear(AudioServer.get_bus_volume_db(bus)), 0.0, 1.0)
	muted = AudioServer.is_bus_mute(bus)
	var config := ConfigFile.new()
	if config.load(settings_path) == OK:
		var saved: Variant = config.get_value("audio", "volume_linear", volume_linear)
		if (saved is float or saved is int) and is_finite(float(saved)):
			volume_linear = clampf(float(saved), 0.0, 1.0)
		var saved_mute: Variant = config.get_value("audio", "muted", muted)
		if saved_mute is bool:
			muted = saved_mute
	_apply()
	changed.emit()

func get_volume_percent() -> float:
	return volume_linear * 100.0

func get_volume_db() -> float:
	# Avoid log(0) / negative infinity in the audio server and persisted settings.
	return linear_to_db(volume_linear) if volume_linear > 0.0 else SILENCE_DB

func set_volume_percent(percent: float) -> void:
	if not is_finite(percent):
		return
	var next: float = clampf(percent / 100.0, 0.0, 1.0)
	if is_equal_approx(next, volume_linear):
		return
	volume_linear = next
	_update()

func set_muted(enabled: bool) -> void:
	if muted == enabled:
		return
	muted = enabled
	_update()

func _apply() -> void:
	# Resolve by name on changes, so bus reordering cannot redirect the control.
	var bus: int = AudioServer.get_bus_index(&"Master")
	AudioServer.set_bus_volume_db(bus, get_volume_db())
	AudioServer.set_bus_mute(bus, muted or volume_linear <= 0.0)

func _update() -> void:
	_apply()
	_dirty = true
	# Audio changes immediately; dragging coalesces disk writes into one save.
	_save_timer.start()
	changed.emit()

func save_settings() -> Error:
	if not _dirty:
		return OK
	_save_timer.stop()
	var config := ConfigFile.new()
	# Preserve settings owned by other features.
	var error: Error = config.load(settings_path)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		push_warning("VizMP: Could not read audio settings: " + error_string(error))
		return error
	config.set_value("audio", "volume_linear", volume_linear)
	config.set_value("audio", "muted", muted)
	var temporary: String = settings_path + ".tmp"
	error = config.save(temporary)
	if error == OK:
		error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(settings_path))
	if error == OK:
		_dirty = false
	else:
		push_warning("VizMP: Could not save audio settings: " + error_string(error))
	return error

func _exit_tree() -> void:
	# A quit or updater restart inside the debounce window must retain the value.
	save_settings()
