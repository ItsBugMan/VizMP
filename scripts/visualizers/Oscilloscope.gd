extends Control
## A retained HDR color attachment provides real phosphor history. The beam
## is a static triangle ribbon; its vertices read signed L/R PCM on the GPU.
const POINT_BUDGETS: Array[int] = [512, 1024, 2048]
const BUFFER_SIZES: Array[int] = [384, 512, 768]
const PALETTES: Array[Color] = [Color(0.12, 1.0, 0.32), Color(1.0, 0.58, 0.12)]
@export_range(0.05, 2.0) var persistence_seconds: float = 0.3
@export var automatic_gain: bool = true
@export_range(0.25, 24.0) var manual_gain: float = 3.0
var _quality: int = -1
var _gain: float = 3.0
var _leased: bool = false
var _initialized: bool = false
var _hud_elapsed: float = 0.0
var _beam_material: ShaderMaterial
var _decay_material: ShaderMaterial
var _crt_material: ShaderMaterial
@onready var phosphor_viewport: SubViewport = $PhosphorBuffer
@onready var beam: MeshInstance2D = $PhosphorBuffer/Beam

func _ready() -> void:
	_beam_material = beam.material.duplicate() as ShaderMaterial
	beam.material = _beam_material
	_decay_material = $PhosphorBuffer/Decay.material.duplicate() as ShaderMaterial
	$PhosphorBuffer/Decay.material = _decay_material
	_crt_material = $CRT.material.duplicate() as ShaderMaterial
	$CRT.material = _crt_material
	_beam_material.set_shader_parameter(&"pcm_texture", StereoPCM.pcm_texture)
	_crt_material.set_shader_parameter(&"phosphor_buffer", phosphor_viewport.get_texture())
	StereoPCM.stream_reset.connect(_clear_history)
	_initialized = true
	set_quality(1)
	_acquire_pcm()

func _enter_tree() -> void:
	if _initialized:
		_acquire_pcm()

func _acquire_pcm() -> void:
	if not _leased:
		_leased = true
		StereoPCM.acquire(self)

func _exit_tree() -> void:
	if _leased:
		_leased = false
		StereoPCM.release(self)

func set_viewport_active(enabled: bool) -> void:
	if enabled:
		_acquire_pcm()
		_clear_history()
	elif _leased:
		_leased = false
		StereoPCM.release(self)

func set_quality(index: int) -> void:
	index = clampi(index, 0, 2)
	if index == _quality:
		return
	_quality = index
	StereoPCM.set_window_size(POINT_BUDGETS[index])
	var resolution: int = BUFFER_SIZES[index]
	phosphor_viewport.size = Vector2i(resolution, resolution)
	_beam_material.set_shader_parameter(&"point_budget", POINT_BUDGETS[index])
	_beam_material.set_shader_parameter(&"buffer_size", float(resolution))
	_crt_material.set_shader_parameter(&"buffer_size", float(resolution))
	_build_ribbon(POINT_BUDGETS[index], resolution)
	_clear_history()

func set_camera_motion(_enabled: bool) -> void:
	pass # Never rotate or animate measured L/R geometry with camera controls.

func set_palette(index: int) -> void:
	_crt_material.set_shader_parameter(&"phosphor_color", PALETTES[clampi(index, 0, 1)])
	$Readout.add_theme_color_override("font_color", PALETTES[clampi(index, 0, 1)].lerp(Color.WHITE, 0.5))

func _build_ribbon(points: int, resolution: int) -> void:
	var segments: int = points - 1
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	vertices.resize(segments * 4)
	uvs.resize(segments * 4)
	indices.resize(segments * 6)
	for i in range(segments):
		var v: int = i * 4
		vertices[v] = Vector2(i, -1)
		vertices[v + 1] = Vector2(i, 1)
		vertices[v + 2] = Vector2(i, -1)
		vertices[v + 3] = Vector2(i, 1)
		uvs[v] = Vector2(0, 0)
		uvs[v + 1] = Vector2(0, 1)
		uvs[v + 2] = Vector2(1, 0)
		uvs[v + 3] = Vector2(1, 1)
		var offset: int = i * 6
		indices[offset] = v
		indices[offset + 1] = v + 1
		indices[offset + 2] = v + 2
		indices[offset + 3] = v + 2
		indices[offset + 4] = v + 1
		indices[offset + 5] = v + 3
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# GPU-displaced canvas vertices need conservative CPU bounds too.
	mesh.custom_aabb = AABB(Vector3(0, 0, -1), Vector3(resolution, resolution, 2))
	beam.mesh = mesh

func _clear_history() -> void:
	if is_instance_valid(phosphor_viewport):
		phosphor_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE

func _process(delta: float) -> void:
	var target_gain: float = manual_gain
	if automatic_gain:
		target_gain = clampf(0.88 / maxf(StereoPCM.peak, 0.005), 0.25, 24.0)
	_gain = lerpf(_gain, target_gain, 1.0 - exp(-delta * (40.0 if target_gain < _gain else 2.0)))
	if automatic_gain:
		# One common instantaneous ceiling prevents an AGC overshoot from
		# flattening L/R independently on the first frame of a loud transient.
		_gain = minf(_gain, 0.95 / maxf(StereoPCM.peak, 0.000001))
	_beam_material.set_shader_parameter(&"valid_frames", StereoPCM.texture_frame_count)
	_beam_material.set_shader_parameter(&"common_gain", _gain)
	_beam_material.set_shader_parameter(&"beam_enabled", 1.0 if StereoPCM.peak > 0.00003 else 0.0)
	_beam_material.set_shader_parameter(&"beam_exposure", minf(delta, 0.05) * 60.0 * 0.05 * 1024.0 / POINT_BUDGETS[_quality])
	_decay_material.set_shader_parameter(&"decay_alpha", 1.0 - exp(-delta / maxf(persistence_seconds, 0.01)))
	_hud_elapsed += delta
	if _hud_elapsed >= 0.1:
		_hud_elapsed = 0.0
		var phase: String = "%+.2f" % StereoPCM.correlation if StereoPCM.correlation_valid else "—"
		var source: String = "DESKTOP" if AudioLoopbackManager.mode == AudioLoopbackManager.Mode.DESKTOP else "FILE"
		$Readout.text = "X: LEFT  /  Y: RIGHT   •   %s   •   CORR %s   •   %.1f ms" % [source, phase,
			1000.0 * mini(StereoPCM.texture_frame_count, POINT_BUDGETS[_quality]) / maxf(StereoPCM.sample_rate, 1.0)]
