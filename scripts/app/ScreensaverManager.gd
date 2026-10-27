extends Node
## Windows screensaver startup, per-user preferences, and one input exit guard.
## Preview HWND embedding is intentionally not attempted in GDScript.
signal exit_requested
enum LaunchMode { APP, SAVER, CONFIG, PREVIEW, INVALID }
const CONFIG_PATH: String = "user://screensaver_config.cfg"
const GRACE_SECONDS: float = 0.5
const CURSOR_IDLE_SECONDS: float = 2.0
const MOUSE_TOLERANCE: float = 8.0
const DEFAULTS: Dictionary = {
	"mode": 1, "quality": 1, "skin": "res://skins/classic-mint.json",
	"audio_source": "desktop", "playlist_directory": "", "recursive": true,
	"volume_db": -12.0, "scope_palette": 0,
}
const ENGINE_VALUE_FLAGS: Array[String] = [
	"--path", "--script", "-s", "--scene", "--audio-driver", "--display-driver",
	"--rendering-driver", "--rendering-method", "--resolution", "--position",
	"--screen", "--max-fps", "--quit-after", "--log-file", "--remote-debug",
	"--editor-pid", "--render-thread", "--audio-output-latency",
]
var launch_mode: LaunchMode = LaunchMode.APP
var parent_handle: String = ""
var preview_handle_valid: bool = false
var config_path: String = CONFIG_PATH
var preferences: Dictionary = DEFAULTS.duplicate()
var session_active: bool = false
var _clock: float = 0.0
var _idle_time: float = 0.0
var _motion: Vector2 = Vector2.ZERO
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var _quitting: bool = false
var _configuration: Window
var _anchor_position: Vector2i
var _poll_global_mouse: bool = false
var _previous_max_fps: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args: PackedStringArray = OS.get_cmdline_args()
	# Versions differ in whether the first list also contains user arguments.
	# Repeated identical flags are idempotent; conflicting commands fail closed.
	args.append_array(OS.get_cmdline_user_args())
	var as_saver: bool = OS.get_executable_path().get_extension().to_lower() == "scr" or OS.has_feature("windows_screensaver")
	var parsed: Dictionary = parse_arguments(args, as_saver)
	launch_mode = parsed.mode
	parent_handle = parsed.handle
	preview_handle_valid = parsed.handle_valid
	print("VizMP: startup mode ", LaunchMode.keys()[launch_mode])
	if launch_mode == LaunchMode.PREVIEW or launch_mode == LaunchMode.INVALID:
		# Godot's main Window cannot be hidden. Minimize before the first frame
		# instead; Entry exits without constructing any visualizer or UI.
		if DisplayServer.get_name() != "headless":
			get_tree().root.mode = Window.MODE_MINIMIZED
	load_preferences()
	set_process(false)
	set_process_input(false)

static func parse_arguments(args: PackedStringArray, screensaver_executable: bool = false) -> Dictionary:
	var saw_saver: bool = false
	var saw_config: bool = false
	var saw_preview: bool = false
	var unknown: bool = false
	var handle: String = ""
	var handle_valid: bool = false
	var skip_value: bool = false
	for original in args:
		var token: String = original.strip_edges()
		if skip_value:
			skip_value = false
			continue
		if token in ENGINE_VALUE_FLAGS:
			skip_value = true
			continue
		if token.is_empty() or token == "--" or token == "++" or token.begins_with("--"):
			continue
		var lower: String = token.to_lower()
		if lower == "/s":
			saw_saver = true
		elif lower == "/c" or lower.begins_with("/c:"):
			saw_config = true
			if lower.begins_with("/c:"):
				handle = token.substr(3).strip_edges()
				handle_valid = valid_window_handle(handle)
		elif lower == "/p" or lower.begins_with("/p:"):
			saw_preview = true
			handle = token.substr(3).strip_edges() if lower.begins_with("/p:") else ""
			handle_valid = valid_window_handle(handle)
		elif (saw_preview or saw_config) and valid_window_handle(token):
			handle = token
			handle_valid = true
		else:
			unknown = true
	var selected: int = LaunchMode.APP
	# Any preview request must NEVER fall through into a fullscreen saver.
	if saw_preview:
		selected = LaunchMode.PREVIEW
	elif saw_saver and saw_config:
		selected = LaunchMode.INVALID
	elif saw_config:
		selected = LaunchMode.CONFIG
	elif saw_saver:
		selected = LaunchMode.INVALID if unknown else LaunchMode.SAVER
	elif screensaver_executable:
		selected = LaunchMode.INVALID if unknown else LaunchMode.SAVER
	return {"mode": selected, "handle": handle, "handle_valid": handle_valid}

static func valid_window_handle(value: String) -> bool:
	if value.is_empty() or value.length() > 20:
		return false
	if value.to_lower().begins_with("0x"):
		return value.length() <= 18 and value.is_valid_hex_number(true) and value.hex_to_int() != 0
	for character in value:
		if character < "0" or character > "9":
			return false
	return value.to_int() > 0

static func normalized_preferences(candidate: Dictionary) -> Dictionary:
	var clean: Dictionary = DEFAULTS.duplicate()
	for key in ["mode", "quality", "scope_palette"]:
		var value: Variant = candidate.get(key, clean[key])
		if value is int:
			clean[key] = clampi(value, 0, 4 if key == "mode" else (2 if key == "quality" else 1))
	for key in ["skin", "playlist_directory"]:
		if candidate.get(key) is String:
			clean[key] = candidate[key].strip_edges()
	if candidate.get("audio_source") in ["desktop", "playlist"]:
		clean.audio_source = candidate.audio_source
	if candidate.get("recursive") is bool:
		clean.recursive = candidate.recursive
	var volume: Variant = candidate.get("volume_db", clean.volume_db)
	if (volume is float or volume is int) and is_finite(float(volume)):
		clean.volume_db = clampf(float(volume), -60.0, 0.0)
	if clean.skin.is_empty():
		clean.skin = DEFAULTS.skin
	return clean

func load_preferences() -> void:
	preferences = DEFAULTS.duplicate()
	var config := ConfigFile.new()
	if config.load(config_path) != OK or config.get_value("screensaver", "version", 0) != 1:
		return
	var data: Dictionary = {}
	for key in DEFAULTS:
		data[key] = config.get_value("screensaver", key, DEFAULTS[key])
	preferences = normalized_preferences(data)

func save_preferences(candidate: Dictionary) -> Error:
	var clean: Dictionary = normalized_preferences(candidate)
	var config := ConfigFile.new()
	config.set_value("screensaver", "version", 1)
	for key in clean:
		config.set_value("screensaver", key, clean[key])
	var temporary: String = config_path + ".tmp"
	var error: Error = config.save(temporary)
	if error != OK:
		return error
	error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(config_path))
	if error == OK:
		preferences = clean
	return error

func configure_primary_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window: Window = get_tree().root
	window.mode = Window.MODE_WINDOWED
	window.current_screen = DisplayServer.get_primary_screen()
	window.borderless = true
	window.mode = Window.MODE_FULLSCREEN
	window.grab_focus()
	print("VizMP: primary saver window configured; fullscreen=", window.mode == Window.MODE_FULLSCREEN,
		"; borderless=", window.borderless, "; primary=", window.current_screen == DisplayServer.get_primary_screen())

func begin_session(configure_display: bool = true) -> void:
	if session_active:
		return
	_previous_mouse_mode = Input.mouse_mode
	_previous_max_fps = Engine.max_fps
	Engine.max_fps = mini(Engine.max_fps, 60) if Engine.max_fps > 0 else 60
	_clock = 0.0
	_idle_time = 0.0
	_motion = Vector2.ZERO
	_quitting = false
	session_active = true
	_poll_global_mouse = configure_display and DisplayServer.get_name() != "headless"
	if configure_display:
		configure_primary_window()
	_anchor_position = DisplayServer.mouse_get_position()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_process(true)
	set_process_input(true)

func end_session() -> void:
	if session_active:
		Input.mouse_mode = _previous_mouse_mode
		Engine.max_fps = _previous_max_fps
	session_active = false
	set_process(false)
	set_process_input(false)

func _process(delta: float) -> void:
	_clock += delta
	_idle_time += delta
	if _poll_global_mouse:
		var position: Vector2i = DisplayServer.mouse_get_position()
		if _clock < GRACE_SECONDS:
			_anchor_position = position
		elif Vector2(position - _anchor_position).length_squared() >= MOUSE_TOLERANCE * MOUSE_TOLERANCE:
			# Also catches movement outside the primary window on another monitor.
			request_exit()
			return
	if _idle_time >= CURSOR_IDLE_SECONDS and Input.mouse_mode != Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func should_exit_on_input(event: InputEvent) -> bool:
	if not session_active:
		return false
	if event is InputEventMouseMotion:
		if not event.relative.is_zero_approx():
			_idle_time = 0.0
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if _clock < GRACE_SECONDS:
			_motion = Vector2.ZERO
			return false
		_motion += event.relative
		return _motion.length_squared() >= MOUSE_TOLERANCE * MOUSE_TOLERANCE
	if _clock < GRACE_SECONDS:
		return false
	if event is InputEventKey:
		return event.pressed
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		return event.pressed
	return false

func _input(event: InputEvent) -> void:
	if should_exit_on_input(event):
		get_viewport().set_input_as_handled()
		request_exit()

func request_exit(code: int = 0) -> void:
	if _quitting:
		return
	_quitting = true
	end_session()
	exit_requested.emit()
	get_tree().quit(code)

func show_configuration(close_on_dismiss: bool = false) -> void:
	if is_instance_valid(_configuration):
		_configuration.grab_focus()
		return
	var script: Script = load("res://scripts/app/ScreensaverConfigDialog.gd")
	_configuration = script.new()
	_configuration.close_on_dismiss = close_on_dismiss
	get_tree().root.add_child(_configuration)
	_configuration.popup_centered_clamped(Vector2i(620, 620), 0.9)

func _exit_tree() -> void:
	end_session()
