extends Control
## Geometry is rebuilt only on strikes. All per-frame work is bounded.
const SEGMENT_LIMIT: int = 1100
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _paths: Array[PackedVector2Array] = []
var _screen_paths: Array[PackedVector2Array] = []
var _cached_size := Vector2.ZERO
var _weights := PackedFloat32Array()
var _flash: float = 0.0
var _age: float = 10.0
var _cooldown: float = 0.0
var _previous_sub: float = 0.0
var _segments: int = 0
var _quality: int = 1
var _time: float = 0.0
var _motion: bool = true
var _clouds: ShaderMaterial

func _ready() -> void:
	var bolt_material := ShaderMaterial.new()
	bolt_material.shader = preload("res://shaders/lightning_bolt.gdshader")
	material = bolt_material
	_rng.randomize()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 4
	_noise.frequency = 5.0
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.show_behind_parent = true
	_clouds = ShaderMaterial.new()
	_clouds.shader = preload("res://shaders/storm_clouds.gdshader")
	background.material = _clouds
	add_child(background)
	AudioAnalyzer.beat_detected.connect(_on_beat)

func set_quality(index: int) -> void:
	_quality = clampi(index, 0, 2)
	_clouds.set_shader_parameter(&"cloud_layers", [4, 6, 9][_quality])

func set_camera_motion(enabled: bool) -> void:
	_motion = enabled

func _on_beat(strength: float) -> void:
	if is_visible_in_tree() and AudioAnalyzer.signal_active and _cooldown <= 0.0:
		strike(maxf(strength, AudioAnalyzer.sub_bass))

func strike(strength: float) -> void:
	_paths.clear()
	_weights.clear()
	_segments = 0
	_age = 0.0
	_flash = clampf(strength, 0.15, 1.0)
	_cooldown = 0.25
	_noise.seed = _rng.randi()
	var start := Vector2(_rng.randf_range(0.2, 0.8), -0.03)
	var finish := Vector2(clampf(start.x + _rng.randf_range(-0.3, 0.3), 0.05, 0.95), 1.04)
	var main := _bolt(start, finish, 6 + _quality, 0.2)
	_paths.append(main)
	_weights.append(1.0)
	var forks: int = 4 + int((AudioAnalyzer.mid + AudioAnalyzer.treble) * (5 + _quality * 4))
	for i in range(forks):
		var origin: Vector2 = main[_rng.randi_range(3, main.size() - 4)]
		var end := origin + Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(0.08, 0.45))
		_paths.append(_bolt(origin, end, 4, 0.07))
		_weights.append(_rng.randf_range(0.15, 0.55))
		if _quality > 0 and i % 2 == 0:
			_paths.append(_bolt(end, end + Vector2(_rng.randf_range(-0.15, 0.15), 0.12), 3, 0.03))
			_weights.append(0.13)
	_clouds.set_shader_parameter(&"strike_x", start.x)
	_rebuild_screen_paths()

func _rebuild_screen_paths() -> void:
	_cached_size = size
	_screen_paths.clear()
	for path in _paths:
		var scaled := PackedVector2Array()
		scaled.resize(path.size())
		for i in range(path.size()): scaled[i] = path[i] * size
		_screen_paths.append(scaled)

func _bolt(start: Vector2, finish: Vector2, depth: int, displacement: float) -> PackedVector2Array:
	var points := PackedVector2Array([start])
	_subdivide(start, finish, depth, displacement, points)
	return points

func _subdivide(start: Vector2, finish: Vector2, depth: int, displacement: float, points: PackedVector2Array) -> void:
	if depth <= 0 or _segments >= SEGMENT_LIMIT:
		points.append(finish)
		_segments += 1
		return
	var midpoint: Vector2 = (start + finish) * 0.5
	var offset: float = _noise.get_noise_2d(midpoint.x * 12.0, midpoint.y * 12.0)
	midpoint += (finish - start).orthogonal().normalized() * displacement * (_rng.randf_range(-0.6, 0.6) + offset)
	_subdivide(start, midpoint, depth - 1, displacement * 0.54, points)
	_subdivide(midpoint, finish, depth - 1, displacement * 0.54, points)

func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_age += delta
	if _motion: _time += delta
	# Sub-bass onset also catches material that has a weak broadband derivative.
	if AudioAnalyzer.signal_active and _cooldown <= 0.0 and AudioAnalyzer.sub_bass > 0.38 and AudioAnalyzer.sub_bass - _previous_sub > 0.045:
		strike(AudioAnalyzer.sub_bass)
	_previous_sub = AudioAnalyzer.sub_bass
	if size != _cached_size: _rebuild_screen_paths()
	_clouds.set_shader_parameter(&"storm_time", _time)
	_clouds.set_shader_parameter(&"flash", _flash * exp(-_age * 7.0))
	var world := get_viewport().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world != null:
		world.environment.tonemap_exposure = 1.0 + _flash * exp(-_age * 10.0) * 0.8
		world.environment.glow_intensity = (0.65 + _flash * exp(-_age * 4.0)) if _quality > 0 else 0.0
	queue_redraw()

func _draw() -> void:
	if _age > 1.8: return
	var energy: float = _flash * (exp(-_age * 11.0) + exp(-_age * 3.8) * 0.22)
	# A short return stroke is a deterministic second peak, never a new bolt.
	energy += _flash * exp(-pow((_age - 0.095) * 45.0, 2.0)) * 0.7
	for i in range(_paths.size()):
		var points: PackedVector2Array = _screen_paths[i]
		var power: float = energy * _weights[i]
		if _quality > 0:
			draw_polyline(points, Color(0.08 * power, 0.25 * power, 0.7 * power), 10.0 * _weights[i], false)
		draw_polyline(points, Color(0.4 * power, 0.8 * power, 2.8 * power), maxf(1.0, 3.0 * _weights[i]), false)
		draw_polyline(points, Color(6.0 * power, 7.0 * power, 9.0 * power), maxf(0.65, 1.2 * _weights[i]), false)
