extends Control
## Decorative strip has no input; every functional control remains accessible.
var _surface: ColorRect
var _art: TextureRect
var _title: Label
var _material: ShaderMaterial

func _ready() -> void:
	custom_minimum_size.y = 86
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface = ColorRect.new()
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/skin_surface.gdshader")
	_surface.material = _material
	add_child(_surface)
	_art = TextureRect.new()
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	_title = Label.new()
	_title.position = Vector2(10, 60)
	_title.add_theme_font_size_override("font_size", 11)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	SkinManager.skin_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	visible = not SkinManager.chrome.is_empty() and not SkinManager.chrome.has("layout")
	_art.texture = SkinManager.artwork
	_title.text = SkinManager.skin_name.to_upper() + " / VIZMP"
	_title.modulate = SkinManager.accent_color
	_material.set_shader_parameter(&"accent", SkinManager.accent_color)
	_material.set_shader_parameter(&"surface_type", ["metal", "plastic", "mech"].find(SkinManager.chrome.get("surface", "metal")))
