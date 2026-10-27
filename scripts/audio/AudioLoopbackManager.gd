extends Node
## Default Windows render-endpoint WASAPI loopback. No microphone is opened.
## Helper PCM -> generator -> DesktopAnalysis [Capture, FFT] -> muted sink.
## Consumers borrow pcm_frames until the next pcm_updated signal.

signal mode_changed(mode: int)
signal status_changed(message: String)
signal pcm_updated

enum Mode { FILE, DESKTOP }
const ANALYSIS_BUS: StringName = &"DesktopAnalysis"
const SINK_BUS: StringName = &"DesktopSilentSink"
const HEADER_BYTES: int = 32
const MAX_PACKETS_PER_FRAME: int = 256

var mode: Mode = Mode.FILE
var status: String = "File playback"
var pcm_frames := PackedVector2Array()
var dropped_packets: int = 0
var dropped_frames: int = 0
var received_frames: int = 0
var sample_rate: int = 0
var capture_discarded_frames: int = 0

var _socket: PacketPeerUDP
var _token := PackedByteArray()
var _pid: int = -1
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _capture: AudioEffectCapture
var _file_player: AudioStreamPlayer
var _file_was_paused: bool = false
var _last_packet_ms: int = 0
var _last_pcm_ms: int = 0
var _last_sequence: int = -1
var _error_path: String
var _monitor_elapsed: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Feed PCM before AudioAnalyzer reads the most recent completed audio FFT.
	process_priority = -10
	_player = AudioStreamPlayer.new()
	_player.name = "DesktopPCM"
	_player.bus = ANALYSIS_BUS
	add_child(_player)
	set_process(false)

func register_file_player(player: AudioStreamPlayer) -> void:
	_file_player = player

func set_mode(next_mode: Mode) -> Error:
	if next_mode == mode:
		return OK
	if next_mode == Mode.DESKTOP:
		var error: Error = _start_desktop()
		if error != OK:
			return error
		if is_instance_valid(_file_player):
			_file_was_paused = _file_player.stream_paused
			_file_player.stream_paused = true
	else:
		_stop_desktop()
		AudioAnalyzer.set_analysis_bus(&"Master")
		if is_instance_valid(_file_player):
			_file_player.stream_paused = _file_was_paused
		_set_status("File playback")
	mode = next_mode
	mode_changed.emit(mode)
	return OK

func _start_desktop() -> Error:
	if OS.get_name() != "Windows":
		return _fail("Desktop loopback currently requires Windows.", ERR_UNAVAILABLE)
	var helper: String = ProjectSettings.globalize_path("res://bin/loopback/VizMPLoopback.exe")
	if OS.has_feature("template"):
		helper = OS.get_executable_path().get_base_dir().path_join("loopback/VizMPLoopback.exe")
	if not FileAccess.file_exists(helper):
		return _fail("Build native/build-loopback.ps1 first; loopback helper is missing.", ERR_FILE_NOT_FOUND)
	var bus: int = AudioServer.get_bus_index(ANALYSIS_BUS)
	var sink: int = AudioServer.get_bus_index(SINK_BUS)
	if bus < 0 or sink < 0:
		return _fail("Load default_bus_layout.tres; desktop buses are missing.", ERR_UNCONFIGURED)
	_capture = null
	for i in range(AudioServer.get_bus_effect_count(bus)):
		var effect: AudioEffect = AudioServer.get_bus_effect(bus, i)
		if effect is AudioEffectCapture:
			_capture = effect as AudioEffectCapture
			AudioServer.set_bus_effect_enabled(bus, i, true)
	if _capture == null:
		return _fail("DesktopAnalysis requires an AudioEffectCapture.", ERR_UNCONFIGURED)
	# Silence ONLY the downstream sink; analysis and PCM remain full amplitude.
	AudioServer.set_bus_send(bus, SINK_BUS)
	AudioServer.set_bus_mute(sink, true)
	AudioServer.set_bus_mute(bus, false)
	AudioServer.set_bus_bypass_effects(bus, false)
	AudioServer.set_bus_volume_db(bus, 0.0)
	_socket = PacketPeerUDP.new()
	var error: Error = _socket.bind(0, "127.0.0.1", 1048576)
	if error != OK:
		_socket = null
		return _fail("Could not bind local audio transport.", error)
	_token = Crypto.new().generate_random_bytes(16)
	_error_path = ProjectSettings.globalize_path("user://loopback_" + _token.hex_encode() + ".txt")
	_pid = OS.create_process(helper, PackedStringArray([
		str(_socket.get_local_port()), _token.hex_encode(), str(OS.get_process_id()), _error_path]), false)
	if _pid <= 0:
		_stop_desktop()
		return _fail("Windows could not launch the loopback helper.", ERR_CANT_FORK)
	if not AudioAnalyzer.set_analysis_bus(ANALYSIS_BUS):
		_stop_desktop()
		AudioAnalyzer.set_analysis_bus(&"Master")
		return _fail("Desktop FFT initialization failed.", ERR_CANT_CREATE)
	_capture.clear_buffer()
	_last_packet_ms = Time.get_ticks_msec()
	_last_pcm_ms = _last_packet_ms
	_last_sequence = -1
	received_frames = 0
	dropped_packets = 0
	dropped_frames = 0
	capture_discarded_frames = 0
	_monitor_elapsed = 0.0
	set_process(true)
	_set_status("Connecting to Windows desktop output...")
	return OK

func _process(delta: float) -> void:
	var count: int = 0
	# Prefer recent audio after a render stall. Bound main-thread work even
	# when a debugger pause has filled the socket's receive buffer.
	if _socket.get_available_packet_count() > 32:
		while _socket.get_available_packet_count() > 16 and count < MAX_PACKETS_PER_FRAME:
			_socket.get_packet()
			count += 1
		if sample_rate > 0:
			_restart_generator(sample_rate)
	while _socket.get_available_packet_count() > 0 and count < MAX_PACKETS_PER_FRAME:
		_accept_packet(_socket.get_packet())
		count += 1
	if _capture != null:
		capture_discarded_frames = _capture.get_discarded_frames()
		var available: int = _capture.get_frames_available()
		if available > 0:
			pcm_frames = _capture.get_buffer(available)
			pcm_updated.emit()
	_monitor_elapsed += delta
	if _monitor_elapsed < 0.5:
		return
	_monitor_elapsed = 0.0
	if not OS.is_process_running(_pid):
		var detail: String = _read_error()
		set_mode(Mode.FILE)
		_set_status("Loopback stopped. " + detail)
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_packet_ms > 2000:
		_set_status("Waiting for Windows output device. " + _read_error())
	elif now - _last_pcm_ms > 750:
		_set_status("Desktop loopback ready / waiting for system audio")
	else:
		_set_status("LIVE DESKTOP / %d Hz" % sample_rate)

func _accept_packet(packet: PackedByteArray) -> void:
	if packet.size() < HEADER_BYTES or packet.slice(0, 4).get_string_from_ascii() != "VMP1":
		return
	if packet.slice(4, 20) != _token:
		return
	var rate: int = packet.decode_u32(24)
	var frames: int = packet.decode_u32(28)
	if rate < 8000 or rate > 384000 or frames > 256 or packet.size() != HEADER_BYTES + frames * 8:
		return
	var sequence: int = packet.decode_u32(20)
	if _last_sequence >= 0:
		var distance: int = (sequence - _last_sequence) & 0xffffffff
		if distance == 0 or distance > 0x7fffffff:
			return # Reject duplicates and reordered packets, including wraparound.
		dropped_packets += distance - 1
	_last_sequence = sequence
	_last_packet_ms = Time.get_ticks_msec()
	if rate != sample_rate or _playback == null:
		_restart_generator(rate)
	if frames == 0:
		return
	# Packed stereo float32 bytes map directly to Vector2; no per-sample loop.
	var pcm: PackedVector2Array = packet.slice(HEADER_BYTES).to_vector2_array()
	if not _playback.can_push_buffer(frames):
		# Backpressure after a stalled render frame: discard old queued audio.
		dropped_frames += frames
		_restart_generator(rate)
	if _playback.push_buffer(pcm):
		received_frames += frames
		_last_pcm_ms = Time.get_ticks_msec()

func _restart_generator(rate: int) -> void:
	_player.stop()
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = rate
	generator.mix_rate_mode = AudioStreamGenerator.MIX_RATE_CUSTOM
	generator.buffer_length = 0.12
	_player.stream = generator
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	sample_rate = rate
	AudioAnalyzer.reset_history()

func _stop_desktop() -> void:
	set_process(false)
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1
	if _socket != null:
		_socket.close()
	_socket = null
	if is_instance_valid(_player):
		_player.stop()
	_playback = null
	if _capture != null:
		_capture.clear_buffer()
	_capture = null
	pcm_frames = PackedVector2Array()
	sample_rate = 0
	if not _error_path.is_empty() and FileAccess.file_exists(_error_path):
		DirAccess.remove_absolute(_error_path)
	_error_path = ""

func _read_error() -> String:
	if FileAccess.file_exists(_error_path):
		return FileAccess.get_file_as_string(_error_path).strip_edges().left(240)
	return ""

func _fail(message: String, error: Error) -> Error:
	_set_status(message)
	return error

func _set_status(message: String) -> void:
	if message != status:
		status = message
		status_changed.emit(status)

func _exit_tree() -> void:
	_stop_desktop()
