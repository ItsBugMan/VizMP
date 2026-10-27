extends Control
const AUDIO_LOADER = preload("res://scripts/audio/AudioStreamLoader.gd")
## Visualizer-only scene. No deck, saved docks, file dialogs or detached windows.
const MAX_TRACKS: int = 10000
const MAX_DIRECTORIES: int = 2000
@export var configure_display: bool = true
@export var start_audio: bool = true
@onready var visualizer: Control = $Visualizer
@onready var player: AudioStreamPlayer = $Player
var playlist: Array[String] = []
var _index: int = 0
var _loading: bool = false
var _stopping: bool = false
var _status_age: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SkinManager.register_root(self)
	var preferences: Dictionary = ScreensaverManager.preferences
	if SkinManager.load_skin(preferences.skin, false) != OK:
		SkinManager.load_skin(SkinManager.BUILTINS[0], false)
	visualizer.set_quality(preferences.quality)
	visualizer.set_scope_palette(preferences.scope_palette)
	visualizer.set_mode(preferences.mode)
	player.volume_db = preferences.volume_db
	player.finished.connect(_play_next)
	AudioLoopbackManager.register_file_player(player)
	ScreensaverManager.begin_session(configure_display)
	get_tree().root.close_requested.connect(ScreensaverManager.request_exit)
	if start_audio:
		_start_audio.call_deferred()

func _start_audio() -> void:
	var preferences: Dictionary = ScreensaverManager.preferences
	if preferences.audio_source == "desktop":
		if AudioLoopbackManager.set_mode(AudioLoopbackManager.Mode.DESKTOP) == OK:
			return
		_status("Desktop capture could not start; trying the configured playlist.")
	AudioLoopbackManager.set_mode(AudioLoopbackManager.Mode.FILE)
	playlist = await scan_directory(preferences.playlist_directory, preferences.recursive)
	if _stopping:
		return
	if playlist.is_empty():
		_status("No playable playlist files found. The visualizer will remain idle.")
		return
	playlist.shuffle()
	_play_next()

func scan_directory(folder: String, recursive: bool) -> Array[String]:
	var found: Array[String] = []
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder):
		return found
	var pending: Array[String] = [folder]
	var visited: int = 0
	var slice_start: int = Time.get_ticks_usec()
	while not pending.is_empty() and visited < MAX_DIRECTORIES and found.size() < MAX_TRACKS:
		var directory := DirAccess.open(pending.pop_back())
		visited += 1
		if directory == null:
			continue
		directory.list_dir_begin()
		var name: String = directory.get_next()
		while not name.is_empty() and found.size() < MAX_TRACKS:
			var path: String = directory.get_current_dir().path_join(name)
			if not name.begins_with(".") and not directory.is_link(path):
				if directory.current_is_dir():
					if recursive and pending.size() + visited < MAX_DIRECTORIES:
						pending.append(path)
				elif AUDIO_LOADER.supports(name):
					found.append(path)
			if Time.get_ticks_usec() - slice_start >= 3000:
				await get_tree().process_frame
				if _stopping:
					directory.list_dir_end()
					return found
				slice_start = Time.get_ticks_usec()
			name = directory.get_next()
		directory.list_dir_end()
	return found

func _play_next() -> void:
	if _loading or _stopping or playlist.is_empty():
		return
	_loading = true
	for attempt in range(playlist.size()):
		if _index >= playlist.size():
			var previous: String = playlist.back()
			playlist.shuffle()
			if playlist.size() > 1 and playlist[0] == previous:
				var replacement: String = playlist[1]
				playlist[1] = playlist[0]
				playlist[0] = replacement
			_index = 0
		var path: String = playlist[_index]
		_index += 1
		var stream: AudioStream = AUDIO_LOADER.load_file(path)
		if stream != null:
			player.stop()
			AudioAnalyzer.reset_history()
			StereoPCM.reset()
			player.stream = stream
			player.stream_paused = false
			player.play()
			_loading = false
			return
		# A directory of broken/removed files must not monopolize the input thread.
		await get_tree().process_frame
		if _stopping:
			_loading = false
			return
	_loading = false
	_status("The selected directory contains no decodable audio files.")

func _status(message: String) -> void:
	$Status.text = message
	$Status.show()
	_status_age = 0.0

func _process(delta: float) -> void:
	if $Status.visible:
		_status_age += delta
		if _status_age > 6.0:
			$Status.hide()

func _exit_tree() -> void:
	_stopping = true
	player.stop()
	player.stream = null
	ScreensaverManager.end_session()
	SkinManager.unregister_root(self)
