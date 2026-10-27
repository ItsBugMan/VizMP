extends Node3D
## GPU owns every particle. CPU updates emission density at analysis cadence.

const PARTICLE_COUNTS: Array[int] = [16384, 32768, 65536]
@onready var particles: GPUParticles3D = $Stars
@onready var camera: Camera3D = $Camera3D
var _material: ShaderMaterial
var _emission_pulse: float = 0.0
var _density: float = 0.65

func _ready() -> void:
	# Scene instances get independent ordinary uniforms, sharing audio globals.
	_material = particles.process_material.duplicate() as ShaderMaterial
	particles.process_material = _material
	AudioAnalyzer.spectrum_updated.connect(_update_density)
	AudioAnalyzer.beat_detected.connect(_on_beat)
	_update_density()

func set_quality(index: int) -> void:
	particles.amount = PARTICLE_COUNTS[clampi(index, 0, 2)]

func set_camera_motion(enabled: bool) -> void:
	camera.motion_enabled = enabled

func _process(delta: float) -> void:
	_emission_pulse *= exp(-delta * 4.0)

func _on_beat(strength: float) -> void:
	_emission_pulse = maxf(_emission_pulse, strength)
	_update_density()

func _update_density() -> void:
	_density = clampf(0.48 + AudioAnalyzer.volume * 0.32 + AudioAnalyzer.bass * 0.1 + _emission_pulse * 0.3, 0.0, 1.0)
	# amount stays fixed during playback; custom shader applies the same ratio.
	particles.amount_ratio = _density
	_material.set_shader_parameter(&"spawn_ratio", _density)
