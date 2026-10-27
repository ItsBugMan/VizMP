extends Node
## Validated data-only skin manifests. One shared Theme per application skin.

signal skin_changed
const BUILTINS: Array[String] = ["res://skins/classic-mint.json", "res://skins/midnight-violet.json", "res://skins/amber-terminal.json", "res://skins/cyberpunk.json", "res://skins/brushed-metal.json", "res://skins/retro-phosphor.json"]
const SETTINGS_PATH: String = "user://skin.cfg"
var current_path: String = ""
var skin_name: String = ""
var active_theme: Theme
var background_color := Color("#10191c")
var last_error: String = ""
var _roots: Array[WeakRef] = []

func _ready() -> void:
	var config := ConfigFile.new()
	var preferred: String = BUILTINS[0]
	if config.load(SETTINGS_PATH) == OK:
		preferred = str(config.get_value("skin", "path", preferred))
	if load_skin(preferred, false) != OK:
		load_skin(BUILTINS[0], false)

func register_root(root: Node) -> void:
	if not root is Control and not root is Window:
		return
	for entry in _roots:
		if entry.get_ref() == root:
			return
	_roots.append(weakref(root))
	root.set("theme", active_theme)

func unregister_root(root: Node) -> void:
	for i in range(_roots.size() - 1, -1, -1):
		if _roots[i].get_ref() == null or _roots[i].get_ref() == root:
			_roots.remove_at(i)

func load_skin(path: String, persist: bool = true) -> Error:
	last_error = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 262144:
		return _reject("Skin is missing or exceeds 256 KB.")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return _reject("Skin must contain a JSON object.")
	var data: Dictionary = parsed
	if data.get("version") != 1 or not data.get("name") is String or not data.get("colors") is Dictionary:
		return _reject("Skin requires version 1, a name, and a colors object.")
	var colors: Dictionary = data.colors
	for key in ["background", "panel", "surface", "border", "accent", "text", "muted"]:
		if not colors.get(key) is String or not Color.html_is_valid(colors[key]):
			return _reject("Invalid or missing skin color: " + key)
	var theme := Theme.new()
	theme.default_font_size = 14
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Cascadia Mono"]) if data.name == "Retro Phosphor" else PackedStringArray(["Segoe UI", "Noto Sans"])
	theme.default_font = font
	var panel: StyleBox = _flat(Color(colors.panel), Color(colors.border), 10)
	var normal: StyleBox = _flat(Color(colors.surface), Color(colors.border), 8)
	var hover: StyleBox = _flat(Color(colors.surface).lightened(0.12), Color(colors.accent), 8)
	var pressed: StyleBox = _flat(Color(colors.surface).darkened(0.18), Color(colors.accent), 8)
	var texture: Texture2D
	var regions: Dictionary = {}
	if data.has("atlas"):
		if not data.atlas is String or not data.get("regions") is Dictionary:
			return _reject("Atlas skins require an atlas path and regions object.")
		var atlas_path: String = data.atlas
		if not atlas_path.is_absolute_path() and not atlas_path.begins_with("res://") and not atlas_path.begins_with("user://"):
			atlas_path = path.get_base_dir().path_join(atlas_path)
		if atlas_path.begins_with("res://") and ResourceLoader.exists(atlas_path, "Texture2D"):
			texture = load(atlas_path) as Texture2D
		else:
			var bitmap := Image.new()
			if bitmap.load(atlas_path) == OK:
				texture = ImageTexture.create_from_image(bitmap)
		if texture == null or texture.get_width() > 8192 or texture.get_height() > 8192:
			return _reject("Atlas must be a readable image no larger than 8192 pixels per side.")
		regions = data.regions
		var margins: Variant = data.get("margins", [4, 4, 4, 4])
		if not _numbers(margins, 4):
			return _reject("Atlas margins must be four nonnegative numbers.")
		for key in regions:
			var region: Variant = regions[key]
			if not _numbers(region, 4) or region[2] <= 0 or region[3] <= 0:
				return _reject("Invalid atlas region: " + str(key))
			if region[0] + region[2] > texture.get_width() or region[1] + region[3] > texture.get_height():
				return _reject("Atlas region falls outside image: " + str(key))
			if margins[0] + margins[2] > region[2] or margins[1] + margins[3] > region[3]:
				return _reject("Nine-slice margins exceed region: " + str(key))
		if regions.has("panel"):
			panel = _textured(texture, regions.panel, margins)
		if regions.has("button_normal"):
			normal = _textured(texture, regions.button_normal, margins)
		if regions.has("button_hover"):
			hover = _textured(texture, regions.button_hover, margins)
		if regions.has("button_pressed"):
			pressed = _textured(texture, regions.button_pressed, margins)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "PopupMenu", panel)
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", _flat(Color(colors.panel), Color(colors.border).darkened(0.3), 8))
	theme.set_stylebox("focus", "Button", _flat(Color.TRANSPARENT, Color(colors.accent), 8))
	for type in ["Label", "Button", "CheckButton", "CheckBox", "OptionButton", "MenuButton", "PopupMenu", "ItemList"]:
		theme.set_color("font_color", type, Color(colors.text))
		theme.set_color("font_hover_color", type, Color(colors.accent))
		theme.set_color("font_pressed_color", type, Color(colors.accent))
		theme.set_color("font_disabled_color", type, Color(colors.muted))
	for type in ["OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", type, normal)
		theme.set_stylebox("hover", type, hover)
		theme.set_stylebox("pressed", type, pressed)
		theme.set_stylebox("focus", type, _flat(Color.TRANSPARENT, Color(colors.accent), 8))
	theme.set_stylebox("panel", "Tree", _flat(Color(colors.background), Color(colors.border), 6))
	theme.set_stylebox("selected", "Tree", pressed)
	theme.set_stylebox("selected_focus", "Tree", pressed)
	theme.set_color("font_color", "Tree", Color(colors.text))
	for state in ["slider", "grabber_area", "grabber_area_highlight"]:
		theme.set_stylebox(state, "HSlider", _flat(Color(colors.accent) if state != "slider" else Color(colors.background), Color(colors.border), 3))
	theme.set_stylebox("panel", "ItemList", _flat(Color(colors.background), Color(colors.border), 6))
	theme.set_stylebox("selected", "ItemList", pressed)
	theme.set_stylebox("selected_focus", "ItemList", pressed)
	theme.set_stylebox("slider", "VSlider", _flat(Color(colors.background), Color(colors.border), 2))
	theme.set_stylebox("grabber_area", "VSlider", _flat(Color(colors.accent), Color(colors.accent), 2))
	theme.set_stylebox("grabber_area_highlight", "VSlider", _flat(Color(colors.accent).lightened(0.2), Color(colors.accent), 2))
	for type in ["VBoxContainer", "HBoxContainer"]:
		theme.set_constant("separation", type, 8)
	theme.set_constant("separation", "HSplitContainer", 8)
	theme.set_constant("separation", "VSplitContainer", 8)
	active_theme = theme
	background_color = Color(colors.background)
	current_path = path
	skin_name = data.name.left(80)
	for i in range(_roots.size() - 1, -1, -1):
		var root: Node = _roots[i].get_ref()
		if root == null:
			_roots.remove_at(i)
		else:
			root.set("theme", active_theme)
	if persist:
		var config := ConfigFile.new()
		config.set_value("skin", "path", path)
		config.save(SETTINGS_PATH)
	skin_changed.emit()
	return OK

func _flat(background: Color, border: Color, margin: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.shadow_color = Color(border, 0.15)
	style.shadow_size = 3
	style.set_content_margin_all(margin)
	return style

func _textured(texture: Texture2D, region: Array, margins: Array) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.region_rect = Rect2(region[0], region[1], region[2], region[3])
	for side in range(4):
		style.set_texture_margin(side, margins[side])
	style.set_content_margin_all(10)
	return style

func _numbers(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count:
		return false
	for item in value:
		if (not item is float and not item is int) or not is_finite(float(item)) or item < 0:
			return false
	return true

func _reject(message: String) -> Error:
	last_error = message
	return ERR_INVALID_DATA
