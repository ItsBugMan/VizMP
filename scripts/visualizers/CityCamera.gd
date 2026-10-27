extends Camera3D
## Remains outside the city footprint even at maximum bass-driven approach.
@export var motion_enabled: bool = true
@export_range(0.0, 0.2) var orbit_speed: float = 0.035
var _angle: float = 0.65
var _radius: float = 85.0
var _bass: float = 0.0
var _drop: float = 0.0

func _ready() -> void:
	AudioAnalyzer.beat_detected.connect(_on_beat)
	_update_pose()

func set_extent(half_extent: float) -> void:
	_radius = maxf(65.0, half_extent * 2.4)
	far = maxf(250.0, _radius * 3.0)
	_update_pose()

func _on_beat(strength: float) -> void:
	_drop = maxf(_drop, strength * clampf(AudioAnalyzer.bass + AudioAnalyzer.sub_bass, 0.0, 1.0))

func _process(delta: float) -> void:
	_drop *= exp(-delta * 2.0)
	if not motion_enabled:
		return
	var target: float = clampf(AudioAnalyzer.bass * 0.75 + AudioAnalyzer.sub_bass * 0.25 + _drop * 0.3, 0.0, 1.0)
	_bass = lerpf(_bass, target, 1.0 - exp(-delta * 2.2))
	_angle = fposmod(_angle + orbit_speed * delta, TAU)
	_update_pose()

func _update_pose() -> void:
	var radius: float = _radius * (1.0 - _bass * 0.15)
	var elevation: float = 0.6 - _bass * 0.18
	position = Vector3(cos(_angle) * cos(elevation), sin(elevation), sin(_angle) * cos(elevation)) * radius
	look_at(Vector3(0.0, 5.0 + _bass * 1.5, 0.0), Vector3.UP)
