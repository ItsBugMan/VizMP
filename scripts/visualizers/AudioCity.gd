extends Node3D
## Build instance transforms once. Height, windows and palette remain GPU-owned.
const GRID_SIDES: Array[int] = [24, 32, 48]
const SPACING: float = 2.2
const MAX_HEIGHT: float = 28.0
const WAVE_COUNT: int = 8
@onready var buildings: MultiMeshInstance3D = $Buildings
@onready var camera: Camera3D = $Camera3D
var half_extent: float = 0.0
var _quality: int = -1
var _waves: Array[Vector4] = []
## Uniform submissions duplicate only these eight vectors, keeping the render
## server's previous array independent from the next main-thread age update.
var _next_wave: int = 0
var _wave_serial: int = 0
var _wave_lifetime: float = 3.0
var _floor_material: ShaderMaterial

func _ready() -> void:
	_floor_material = $Floor.material_override.duplicate() as ShaderMaterial
	$Floor.material_override = _floor_material
	_waves.resize(WAVE_COUNT)
	_floor_material.set_shader_parameter(&"shockwaves", _waves.duplicate())
	AudioAnalyzer.beat_detected.connect(_on_beat)
	set_quality(1)

func set_quality(index: int) -> void:
	index = clampi(index, 0, 2)
	if index == _quality:
		return
	_quality = index
	_build_grid(GRID_SIDES[index])

func set_camera_motion(enabled: bool) -> void:
	camera.motion_enabled = enabled

func _build_grid(side: int) -> void:
	half_extent = side * SPACING * 0.5
	var transforms: Array[Transform3D] = []
	var custom_data: Array[Color] = []
	var random := RandomNumberGenerator.new()
	random.seed = 673921
	for row in range(side):
		for column in range(side):
			if row % 8 == 0 or column % 8 == 0:
				continue # Broad avenues through each group of eight cells.
			var width: float = random.randf_range(0.9, 1.5)
			var depth: float = random.randf_range(0.9, 1.5)
			var origin := Vector3((column - side * 0.5 + 0.5) * SPACING, 0.0, (row - side * 0.5 + 0.5) * SPACING)
			transforms.append(Transform3D(Basis.from_scale(Vector3(width, 1.0, depth)), origin))
			var bin_index: int = custom_data.size() % AudioAnalyzer.BIN_COUNT
			custom_data.append(Color((bin_index + 0.5) / AudioAnalyzer.BIN_COUNT, random.randf(), random.randf(), 1.0))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true # Must be configured before instance_count.
	multimesh.mesh = BoxMesh.new()
	multimesh.instance_count = transforms.size()
	multimesh.custom_aabb = AABB(Vector3(-half_extent - 1.0, -0.1, -half_extent - 1.0), Vector3(half_extent * 2.0 + 2.0, MAX_HEIGHT + 0.2, half_extent * 2.0 + 2.0))
	for i in range(transforms.size()):
		multimesh.set_instance_transform(i, transforms[i])
		multimesh.set_instance_custom_data(i, custom_data[i])
	buildings.multimesh = multimesh
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2.ONE * (half_extent * 2.0 + 8.0)
	$Floor.mesh = floor_mesh
	camera.set_extent(half_extent)
	_wave_lifetime = half_extent * 3.0 / 24.0 + 0.5

func _on_beat(strength: float) -> void:
	_wave_serial += 1
	var angle: float = _wave_serial * 2.399963
	var origin := Vector2(cos(angle), sin(angle)) * half_extent * 0.18
	_waves[_next_wave] = Vector4(origin.x, origin.y, 0.0, clampf(strength, 0.0, 1.0))
	_next_wave = (_next_wave + 1) % WAVE_COUNT
	_floor_material.set_shader_parameter(&"shockwaves", _waves.duplicate())

func _process(delta: float) -> void:
	var changed: bool = false
	for i in range(WAVE_COUNT):
		var wave: Vector4 = _waves[i]
		if wave.w <= 0.0:
			continue
		wave.z += delta
		if wave.z > _wave_lifetime:
			wave.w = 0.0
		_waves[i] = wave
		changed = true
	if changed:
		_floor_material.set_shader_parameter(&"shockwaves", _waves.duplicate())
