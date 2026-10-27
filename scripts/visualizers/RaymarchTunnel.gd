extends Control
## Integrate speed: changing bass changes velocity, never teleports position.
const PERIOD: float = TAU * 100.0
const STEP_BUDGETS: Array[int] = [48, 72, 112]
const FOLD_BUDGETS: Array[int] = [3, 4, 5]
var motion_enabled: bool = true
var flight_distance: float = 0.0
var _speed: float = 1.0
var _material: ShaderMaterial

func _ready() -> void:
	_material = $Tunnel.material.duplicate() as ShaderMaterial
	$Tunnel.material = _material
	set_quality(1)

func set_quality(index: int) -> void:
	index = clampi(index, 0, 2)
	_material.set_shader_parameter(&"march_steps", STEP_BUDGETS[index])
	_material.set_shader_parameter(&"fold_limit", FOLD_BUDGETS[index])

func set_camera_motion(enabled: bool) -> void:
	motion_enabled = enabled

func _process(delta: float) -> void:
	# Audio never changes the camera path or velocity. Energy drives emission.
	_speed = lerpf(_speed, 1.8, 1.0 - exp(-delta * 3.0))
	if motion_enabled:
		flight_distance = fposmod(flight_distance + _speed * delta, PERIOD)
		_material.set_shader_parameter(&"flight_distance", flight_distance)
