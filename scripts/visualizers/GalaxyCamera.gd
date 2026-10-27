extends Camera3D
## Bounded, deterministic camera motion; no per-frame random jitter.

@export var motion_enabled: bool = true
@export_range(25.0, 60.0) var orbit_radius: float = 34.0
@export_range(0.0, 0.1) var orbit_speed: float = 0.025
@export_range(0.0, 0.2) var shake_strength: float = 0.06

var _angle: float = 0.15
var _clock: float = 0.0
var _energy: float = 0.0

func _ready() -> void:
	_update_pose()

func _process(delta: float) -> void:
	_clock = fmod(_clock + delta, 3600.0)
	var target: float = AudioAnalyzer.beat_pulse if motion_enabled else 0.0
	_energy = lerpf(_energy, target, 1.0 - exp(-delta * 14.0))
	if motion_enabled:
		_angle = fmod(_angle + orbit_speed * delta * (1.0 + AudioAnalyzer.sub_bass * 0.5), TAU)
	_update_pose()

func _update_pose() -> void:
	var elevation: float = 0.56 + (sin(_clock * 0.07) * 0.045 if motion_enabled else 0.0)
	position = Vector3(cos(_angle) * cos(elevation), sin(elevation), sin(_angle) * cos(elevation)) * orbit_radius
	var offset := Vector3(sin(_clock * 17.0), sin(_clock * 23.0 + 0.7), cos(_clock * 19.0)) * shake_strength * _energy
	look_at(offset, Vector3.UP)
	fov = 58.0 + _energy * 0.7
