extends Control
## One full-screen pass; a static glyph atlas replaces thousands of Labels.
const GLYPHS: String = " .,:;i1tfLCG08@#"
var _material: ShaderMaterial
var _atlas: SubViewport
var _time: float = 0.0
var _energy: float = 0.0
var _motion: bool = true
var _quality: int = 1

func _ready() -> void:
	_atlas = SubViewport.new()
	_atlas.size = Vector2i(512, 48)
	_atlas.transparent_bg = true
	_atlas.disable_3d = true
	_atlas.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_atlas)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "DejaVu Sans Mono"])
	font.font_weight = 600
	for i in range(GLYPHS.length()):
		var label := Label.new()
		label.text = GLYPHS[i]
		label.position = Vector2(i * 32, 0)
		label.size = Vector2(32, 48)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", 34)
		_atlas.add_child(label)
	var rain := ColorRect.new()
	rain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/ascii_rain.gdshader")
	_material.set_shader_parameter(&"glyph_atlas", _atlas.get_texture())
	_material.set_shader_parameter(&"portrait", preload("res://assets/portraits/brow-mask.png"))
	rain.material = _material
	add_child(rain)

func set_quality(index: int) -> void:
	_quality = clampi(index, 0, 2)

func set_camera_motion(enabled: bool) -> void:
	_motion = enabled

func _process(delta: float) -> void:
	var active: bool = AudioAnalyzer.signal_active and AudioAnalyzer.volume > 0.0001
	if active and _motion: _time += delta
	_energy = lerpf(_energy, AudioAnalyzer.volume if active else 0.0, 1.0 - exp(-delta * 12.0))
	_material.set_shader_parameter(&"rain_time", _time)
	_material.set_shader_parameter(&"energy", _energy)
	_material.set_shader_parameter(&"signal_active", active)
	_material.set_shader_parameter(&"aspect", size.x / maxf(size.y, 1.0))
	_material.set_shader_parameter(&"columns", clampf([160.0, 240.0, 320.0][_quality] * maxf(size.y / 1080.0, 0.65), 48.0, minf(720.0, maxf(48.0, size.x / 4.0))))
