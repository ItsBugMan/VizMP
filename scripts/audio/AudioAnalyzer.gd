extends Node
## Autoload named AudioAnalyzer; deliberately no class_name collision.
## Analyzes audio routed THROUGH Godot's Master bus, not desktop loopback.
## Consumers borrow the arrays below: do not mutate them. Use duplicate() if
## retaining a historical frame. The buffers are updated in place at 60 Hz.

signal spectrum_updated
signal beat_detected(strength: float)

const BIN_COUNT: int = 64
const MIN_HZ: float = 20.0
const MAX_HZ: float = 20000.0
const ANALYSIS_STEP: float = 1.0 / 60.0

@export_range(-100.0, -20.0) var floor_db: float = -72.0
@export_range(1.0, 100.0) var attack_speed: float = 35.0
@export_range(1.0, 30.0) var release_speed: float = 9.0
@export_range(1.0, 4.0) var beat_ratio: float = 1.45
@export_range(0.0, 10.0) var derivative_threshold: float = 0.35
@export_range(0.05, 0.5) var beat_cooldown: float = 0.16
@export_range(0.00001, 0.1) var silence_gate: float = 0.0001

var spectrum := PackedFloat32Array() # Smoothed display energy [0, 1].
var spectrum_left := PackedFloat32Array()
var spectrum_right := PackedFloat32Array()
var raw_spectrum := PackedFloat32Array() # Unsquashed linear magnitudes.
var frequency_edges := PackedFloat32Array() # 65 logarithmic boundaries.
var sub_bass: float = 0.0 # 20–60 Hz
var bass: float = 0.0 # 60–250 Hz
var mid: float = 0.0 # 250–4000 Hz
var treble: float = 0.0 # 4000–12000 Hz
var highs: float = 0.0 # 12000–20000 Hz
var volume: float = 0.0 # Spectrum-derived level, NOT calibrated RMS.
var volume_derivative: float = 0.0 # Linear magnitude / second.
var beat_pulse: float = 0.0 # Immediate onset, exponential decay [0, 1].
var is_ready: bool = false

var _effect: AudioEffectSpectrumAnalyzer
var _instance: AudioEffectSpectrumAnalyzerInstance
var _bus_index: int = -1
var _effect_index: int = -1
var _owns_effect: bool = false
var _elapsed: float = 0.0
var _clock: float = 0.0
var _last_beat: float = -10.0
var _baseline: float = 0.0
var _previous_level: float = 0.0
var _warmup: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Reuse these arrays for the entire session, avoiding per-bin allocations.
	spectrum.resize(BIN_COUNT)
	spectrum_left.resize(BIN_COUNT)
	spectrum_right.resize(BIN_COUNT)
	raw_spectrum.resize(BIN_COUNT)
	frequency_edges.resize(BIN_COUNT + 1)
	var upper: float = minf(MAX_HZ, AudioServer.get_mix_rate() * 0.5)
	for i in range(BIN_COUNT + 1):
		frequency_edges[i] = MIN_HZ * pow(upper / MIN_HZ, float(i) / BIN_COUNT)
	_bus_index = AudioServer.get_bus_index(&"Master")
	if _bus_index < 0:
		push_error("VizMP: Master audio bus is missing.")
		set_process(false)
		return
	# Reuse a configured analyzer instead of adding duplicates on scene changes.
	for i in range(AudioServer.get_bus_effect_count(_bus_index)):
		var candidate := AudioServer.get_bus_effect(_bus_index, i)
		if candidate is AudioEffectSpectrumAnalyzer:
			_effect = candidate as AudioEffectSpectrumAnalyzer
			_effect_index = i
			break
	if _effect == null:
		_effect = AudioEffectSpectrumAnalyzer.new()
		_effect.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048
		_effect.buffer_length = 0.25
		_effect_index = AudioServer.get_bus_effect_count(_bus_index)
		AudioServer.add_bus_effect(_bus_index, _effect)
		_owns_effect = true
	AudioServer.set_bus_effect_enabled(_bus_index, _effect_index, true)
	# Effect instances are created by AudioServer, not by the resource itself.
	_instance = AudioServer.get_bus_effect_instance(_bus_index, _effect_index) as AudioEffectSpectrumAnalyzerInstance
	is_ready = _instance != null
	if not is_ready:
		push_error("VizMP: Could not acquire spectrum analyzer instance.")
		set_process(false)

func _process(delta: float) -> void:
	_clock += delta
	beat_pulse *= exp(-8.0 * delta)
	_elapsed += delta
	if _elapsed < ANALYSIS_STEP or not is_ready:
		return
	# One current sample per tick; never repeat stale FFT reads to catch up.
	var dt: float = _elapsed
	_elapsed = fmod(_elapsed, ANALYSIS_STEP)
	var total: float = 0.0
	for i in range(BIN_COUNT):
		var stereo: Vector2 = _instance.get_magnitude_for_frequency_range(
			frequency_edges[i], frequency_edges[i + 1],
			AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX)
		var magnitude: float = (stereo.x + stereo.y) * 0.5
		raw_spectrum[i] = magnitude
		total += magnitude
		spectrum[i] = _smooth(spectrum[i], _display_energy(magnitude), dt)
		spectrum_left[i] = _smooth(spectrum_left[i], _display_energy(stereo.x), dt)
		spectrum_right[i] = _smooth(spectrum_right[i], _display_energy(stereo.y), dt)
	# Broad bands use exact Hz queries, rather than averages of display bins.
	sub_bass = _smooth(sub_bass, _band(20.0, 60.0), dt)
	bass = _smooth(bass, _band(60.0, 250.0), dt)
	mid = _smooth(mid, _band(250.0, 4000.0), dt)
	treble = _smooth(treble, _band(4000.0, 12000.0), dt)
	highs = _smooth(highs, _band(12000.0, MAX_HZ), dt)
	var level: float = total / BIN_COUNT
	volume = _smooth(volume, _display_energy(level), dt)
	_detect_beat(level, dt)
	spectrum_updated.emit()

func _detect_beat(level: float, dt: float) -> void:
	# Differentiate unsquashed magnitudes: log compression would amplify noise.
	volume_derivative = (level - _previous_level) / maxf(dt, 0.000001)
	_previous_level = level
	_warmup += dt
	# Compare against the OLD baseline so the onset cannot raise its own gate.
	var threshold: float = maxf(_baseline * beat_ratio, silence_gate)
	if (_warmup > 0.35 and level > threshold
			and volume_derivative > derivative_threshold
			and _clock - _last_beat >= beat_cooldown):
		_last_beat = _clock
		beat_pulse = clampf((level - threshold) / maxf(threshold, 0.001), 0.0, 1.0)
		beat_detected.emit(beat_pulse)
	_baseline = lerpf(_baseline, level, 1.0 - exp(-dt / 0.65))

func _band(low: float, high: float) -> float:
	var upper: float = frequency_edges[BIN_COUNT]
	if low >= upper:
		return 0.0
	var value: Vector2 = _instance.get_magnitude_for_frequency_range(
		low, minf(high, upper), AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX)
	return _display_energy((value.x + value.y) * 0.5)

func _display_energy(magnitude: float) -> float:
	# Exact silence must remain zero; guard log(0) with a small positive value.
	return clampf((linear_to_db(maxf(magnitude, 0.000000001)) - floor_db) / -floor_db, 0.0, 1.0)

func _smooth(current: float, target: float, dt: float) -> float:
	var rate: float = attack_speed if target > current else release_speed
	return lerpf(current, target, 1.0 - exp(-rate * dt))

func reset_history() -> void:
	# Call on track changes or seeks to avoid a false beat from the discontinuity.
	_baseline = 0.0
	_previous_level = 0.0
	_warmup = 0.0
	beat_pulse = 0.0
	volume_derivative = 0.0
	_last_beat = _clock

func _exit_tree() -> void:
	# Remove only our own resource, even if another system reordered effects.
	var bus: int = AudioServer.get_bus_index(&"Master")
	if not _owns_effect or bus < 0:
		return
	for i in range(AudioServer.get_bus_effect_count(bus)):
		if AudioServer.get_bus_effect(bus, i) == _effect:
			AudioServer.remove_bus_effect(bus, i)
			break
