extends Control
## One active mode. Switching releases the previous viewport and GPU owners.

const GALAXY_SCENE: PackedScene = preload("res://scenes/visualizers/ParticleGalaxy.tscn")
const TUNNEL_SCENE: PackedScene = preload("res://scenes/visualizers/RaymarchTunnel.tscn")
const CITY_SCENE: PackedScene = preload("res://scenes/visualizers/AudioCity.tscn")
const SCOPE_SCENE: PackedScene = preload("res://scenes/visualizers/Oscilloscope.tscn")
const RENDER_SCALES: Array[float] = [0.7, 0.85, 1.0]
const TUNNEL_SHRINK: Array[int] = [3, 2, 1]
enum Mode { RADIAL, GALAXY, TUNNEL, CITY, SCOPE }
signal mode_changed(selected: int)
signal scope_palette_changed(selected: int)
var mode: int = 0
var quality: int = 1
var camera_motion: bool = true
var scope_palette: int = 0
var _container: SubViewportContainer
var _viewport: SubViewport
var _active_visualizer: Node

func set_mode(next_mode: int) -> void:
	next_mode = clampi(next_mode, Mode.RADIAL, Mode.SCOPE)
	if next_mode == mode:
		return
	mode = next_mode
	_release_active()
	$Radial.visible = mode == 0
	if mode == 0:
		mode_changed.emit(mode)
		return
	_container = SubViewportContainer.new()
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.stretch = true
	var grade := ShaderMaterial.new()
	grade.shader = preload("res://shaders/visualizer_grade.gdshader")
	_container.material = grade
	_container.stretch_shrink = TUNNEL_SHRINK[quality] if mode == Mode.TUNNEL else 1
	add_child(_container)
	_viewport = SubViewport.new()
	var canvas_mode: bool = mode == Mode.TUNNEL or mode == Mode.SCOPE
	_viewport.use_hdr_2d = true
	_viewport.own_world_3d = true
	_viewport.disable_3d = canvas_mode
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.scaling_3d_scale = RENDER_SCALES[quality]
	_container.add_child(_viewport)
	match mode:
		Mode.GALAXY: _active_visualizer = GALAXY_SCENE.instantiate()
		Mode.TUNNEL: _active_visualizer = TUNNEL_SCENE.instantiate()
		Mode.CITY: _active_visualizer = CITY_SCENE.instantiate()
		Mode.SCOPE: _active_visualizer = SCOPE_SCENE.instantiate()
	_viewport.add_child(_active_visualizer)
	_apply_environment()
	_active_visualizer.set_quality(quality)
	_active_visualizer.set_camera_motion(camera_motion)
	if mode == Mode.SCOPE:
		_active_visualizer.set_palette(scope_palette)
	mode_changed.emit(mode)

func set_quality(index: int) -> void:
	quality = clampi(index, 0, 2)
	if is_instance_valid(_active_visualizer):
		_apply_environment()
		_active_visualizer.set_quality(quality)
		_viewport.scaling_3d_scale = RENDER_SCALES[quality]
		_container.stretch_shrink = TUNNEL_SHRINK[quality] if mode == Mode.TUNNEL else 1

func set_camera_motion(enabled: bool) -> void:
	camera_motion = enabled
	if is_instance_valid(_active_visualizer):
		_active_visualizer.set_camera_motion(enabled)

func set_scope_palette(index: int) -> void:
	scope_palette = clampi(index, 0, 1)
	if mode == Mode.SCOPE and is_instance_valid(_active_visualizer):
		_active_visualizer.set_palette(scope_palette)
	scope_palette_changed.emit(scope_palette)

func _release_active() -> void:
	if is_instance_valid(_container):
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		remove_child(_container)
		_container.queue_free()
	_container = null
	_viewport = null
	_active_visualizer = null

func _apply_environment() -> void:
	if _viewport == null: return
	_viewport.msaa_3d = Viewport.MSAA_4X if quality == 2 else Viewport.MSAA_DISABLED
	var world := _active_visualizer.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world == null: world = _viewport.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world == null:
		world = WorldEnvironment.new()
		world.name = "WorldEnvironment"
		world.environment = Environment.new()
		world.environment.background_mode = Environment.BG_CANVAS
		_viewport.add_child(world)
	else:
		world.environment = world.environment.duplicate() as Environment
	var env := world.environment
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = quality > 0
	env.glow_intensity = 0.85 if quality == 2 else 0.65
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	env.glow_strength = 1.15
	env.set_glow_level(2, 0.8)
	env.set_glow_level(4, 0.4)
	env.ssao_enabled = mode == Mode.CITY and quality > 0
	env.ssao_radius = 2.0
	env.ssao_intensity = 1.4
	env.ssao_detail = 0.6
	env.ssr_enabled = mode == Mode.CITY and quality == 2
	env.ssr_max_steps = 48
	env.ssr_depth_tolerance = 0.25
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.26, 0.34, 0.5)
	env.ambient_light_energy = 0.65
