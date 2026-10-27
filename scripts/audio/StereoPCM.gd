extends Node
## Single owner of the file PCM tap; borrows desktop PCM from its existing owner.
## No FFT magnitudes are used to reconstruct stereo phase.
signal stream_reset
signal texture_updated
const RING_CAPACITY: int = 8192
const TEXTURE_WIDTH: int = 2048
const STALE_SECONDS: float = 0.12
var pcm_texture: ImageTexture
var texture_frame_count: int = 0
var sample_rate: float = 44100.0
var correlation: float = 0.0 # DC-removed Pearson correlation of the texture window.
var correlation_valid: bool = false
var peak: float = 0.0
var rms: Vector2 = Vector2.ZERO
var sequence: int = 0
var consumer_count: int = 0
var capture_discarded_frames: int = 0
var _ring := PackedVector2Array()
var _pixels := PackedByteArray()
var _image: Image
var _write: int = 0
var _count: int = 0
var _dirty: bool = false
var _age: float = 0.0
var _capture: AudioEffectCapture
var _owners: Dictionary = {}
var _owns_capture: bool = false
var _owner_elapsed: float = 0.0
var _window_frames: int = 1024

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -5 # After desktop drain (-10), before visualizer callbacks.
	_ring.resize(RING_CAPACITY)
	_pixels.resize(TEXTURE_WIDTH * 8)
	_image = Image.create_from_data(TEXTURE_WIDTH, 1, false, Image.FORMAT_RGF, _pixels)
	pcm_texture = ImageTexture.create_from_image(_image)
	_ensure_file_capture()
	AudioLoopbackManager.pcm_updated.connect(_on_desktop_pcm)
	AudioLoopbackManager.mode_changed.connect(_on_source_changed)
	set_process(false)

func _ensure_file_capture() -> void:
	var bus: int = AudioServer.get_bus_index(&"Master")
	for i in range(AudioServer.get_bus_effect_count(bus)):
		var effect: AudioEffect = AudioServer.get_bus_effect(bus, i)
		if effect is AudioEffectCapture:
			_capture = effect as AudioEffectCapture
			return
	_capture = AudioEffectCapture.new()
	_capture.resource_name = "File PCM"
	_capture.buffer_length = 0.25
	AudioServer.add_bus_effect(bus, _capture)
	_owns_capture = true
	_sync_capture_enabled()

func acquire(owner: Node) -> void:
	var id: int = owner.get_instance_id()
	if _owners.has(id):
		return
	_owners[id] = weakref(owner)
	consumer_count = _owners.size()
	if consumer_count == 1:
		reset()
	_sync_capture_enabled()
	set_process(true)

func release(owner: Node) -> void:
	_owners.erase(owner.get_instance_id())
	consumer_count = _owners.size()
	_sync_capture_enabled()
	if consumer_count == 0:
		set_process(false)
		reset()

func set_window_size(frames: int) -> void:
	# The active scope's geometry and correlation meter use the same window.
	_window_frames = clampi(frames, 2, TEXTURE_WIDTH)
	_dirty = _count > 0

func _sync_capture_enabled() -> void:
	# Resolve effect by resource identity: the EQ can insert/reorder Master effects.
	var bus: int = AudioServer.get_bus_index(&"Master")
	for i in range(AudioServer.get_bus_effect_count(bus)):
		if AudioServer.get_bus_effect(bus, i) == _capture:
			AudioServer.set_bus_effect_enabled(bus, i, consumer_count > 0 and AudioLoopbackManager.mode == AudioLoopbackManager.Mode.FILE)
			break

func _on_source_changed(_mode: int) -> void:
	reset()
	_sync_capture_enabled()

func reset() -> void:
	_clear_recent()
	stream_reset.emit()

func _clear_recent() -> void:
	_write = 0
	_count = 0
	_age = 0.0
	texture_frame_count = 0
	correlation = 0.0
	correlation_valid = false
	peak = 0.0
	rms = Vector2.ZERO
	if _capture != null:
		_capture.clear_buffer()
	_pixels.fill(0)
	_image.set_data(TEXTURE_WIDTH, 1, false, Image.FORMAT_RGF, _pixels)
	pcm_texture.update(_image)
	_dirty = false
	sequence += 1

func _on_desktop_pcm() -> void:
	if consumer_count > 0 and AudioLoopbackManager.mode == AudioLoopbackManager.Mode.DESKTOP:
		_ingest(AudioLoopbackManager.pcm_frames)

func _ingest(frames: PackedVector2Array) -> void:
	# Bounded recent history. Stereo pairs are never smoothed or split apart.
	for i in range(maxi(0, frames.size() - RING_CAPACITY), frames.size()):
		var sample: Vector2 = frames[i]
		if not is_finite(sample.x) or not is_finite(sample.y):
			sample = Vector2.ZERO
		_ring[_write] = sample
		_write = (_write + 1) & (RING_CAPACITY - 1)
	_count = mini(RING_CAPACITY, _count + frames.size())
	if not frames.is_empty():
		_age = 0.0
		_dirty = true

func _process(delta: float) -> void:
	# Dead owners cannot leave the audio tap enabled after an unexpected free.
	_owner_elapsed += delta
	if _owner_elapsed >= 1.0:
		_owner_elapsed = 0.0
		for id in _owners.keys():
			if _owners[id].get_ref() == null:
				_owners.erase(id)
	if consumer_count != _owners.size():
		consumer_count = _owners.size()
		_sync_capture_enabled()
		if consumer_count == 0:
			set_process(false)
			reset()
			return
	_age += delta
	sample_rate = AudioServer.get_mix_rate()
	if AudioLoopbackManager.mode == AudioLoopbackManager.Mode.FILE:
		var available: int = _capture.get_frames_available()
		capture_discarded_frames = _capture.get_discarded_frames()
		if available > 0:
			_ingest(_capture.get_buffer(available))
	if _dirty:
		_publish_texture()
	elif _age > STALE_SECONDS and texture_frame_count > 0:
		# Blank the input without erasing the phosphor's natural afterglow.
		_clear_recent()

func _publish_texture() -> void:
	texture_frame_count = mini(_count, _window_frames)
	var start: int = (_write - texture_frame_count) & (RING_CAPACITY - 1)
	var sum_left: float = 0.0
	var sum_right: float = 0.0
	var square_left: float = 0.0
	var square_right: float = 0.0
	var cross: float = 0.0
	peak = 0.0
	for i in range(texture_frame_count):
		var sample: Vector2 = _ring[(start + i) & (RING_CAPACITY - 1)]
		_pixels.encode_float(i * 8, sample.x)
		_pixels.encode_float(i * 8 + 4, sample.y)
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
		sum_left += sample.x
		sum_right += sample.y
		square_left += sample.x * sample.x
		square_right += sample.y * sample.y
		cross += sample.x * sample.y
	var count: float = maxf(texture_frame_count, 1)
	rms = Vector2(sqrt(square_left / count), sqrt(square_right / count))
	var left_variance: float = maxf(0.0, square_left - sum_left * sum_left / count)
	var right_variance: float = maxf(0.0, square_right - sum_right * sum_right / count)
	correlation_valid = left_variance / count > 0.000000001 and right_variance / count > 0.000000001
	correlation = clampf((cross - sum_left * sum_right / count) / sqrt(maxf(left_variance * right_variance, 1e-24)), -1.0, 1.0) if correlation_valid else 0.0
	_image.set_data(TEXTURE_WIDTH, 1, false, Image.FORMAT_RGF, _pixels)
	pcm_texture.update(_image)
	_dirty = false
	sequence += 1
	texture_updated.emit()

func _exit_tree() -> void:
	var bus: int = AudioServer.get_bus_index(&"Master")
	for i in range(AudioServer.get_bus_effect_count(bus)):
		if AudioServer.get_bus_effect(bus, i) == _capture:
			if _owns_capture:
				AudioServer.remove_bus_effect(bus, i)
			else:
				AudioServer.set_bus_effect_enabled(bus, i, false)
			break
