extends VBoxContainer
## File-output EQ; desktop mode observes the Windows mix without altering it.
var _effect: AudioEffectEQ6
var _sliders: Array[VSlider] = []
const FREQUENCIES: Array[float] = [32.0, 100.0, 320.0, 1000.0, 3200.0, 10000.0]

func _ready() -> void:
	_effect = AudioEffectEQ6.new()
	_effect.resource_name = "VizMP file EQ"
	_ensure_effect()
	var note := Label.new()
	note.text = "FILE OUTPUT / ±12 dB"
	add_child(note)
	var bands := HBoxContainer.new()
	bands.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(bands)
	for i in range(_effect.get_band_count()):
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bands.add_child(column)
		var slider := VSlider.new()
		slider.min_value = -12.0
		slider.max_value = 12.0
		slider.step = 0.5
		slider.custom_minimum_size.y = 80
		slider.size_flags_vertical = Control.SIZE_EXPAND_FILL
		slider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var frequency: float = FREQUENCIES[i]
		slider.tooltip_text = "%s Hz: 0 dB" % str(frequency)
		column.add_child(slider)
		var label := Label.new()
		label.text = str(frequency / 1000.0) + "k" if frequency >= 1000.0 else str(int(frequency))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
		slider.value_changed.connect(func(value: float) -> void:
			_effect.set_band_gain_db(i, value)
			slider.tooltip_text = "%s Hz: %+.1f dB" % [str(frequency), value]
			AudioAnalyzer.reset_history())
		_sliders.append(slider)
	var reset := Button.new()
	reset.text = "Reset EQ"
	reset.pressed.connect(func() -> void:
		for slider in _sliders:
			slider.value = 0.0)
	add_child(reset)
	AudioLoopbackManager.mode_changed.connect(_on_mode)
	_on_mode(AudioLoopbackManager.mode)

func _on_mode(mode: int) -> void:
	for slider in _sliders:
		slider.editable = mode == AudioLoopbackManager.Mode.FILE

func _enter_tree() -> void:
	# Reparenting a dock exits/re-enters the tree without running _ready again.
	if _effect != null:
		_ensure_effect()

func _ensure_effect() -> void:
	var bus: int = AudioServer.get_bus_index(&"Master")
	for i in range(AudioServer.get_bus_effect_count(bus)):
		if AudioServer.get_bus_effect(bus, i) == _effect:
			return
	AudioServer.add_bus_effect(bus, _effect, 0)

func _exit_tree() -> void:
	var bus: int = AudioServer.get_bus_index(&"Master")
	for i in range(AudioServer.get_bus_effect_count(bus)):
		if AudioServer.get_bus_effect(bus, i) == _effect:
			AudioServer.remove_bus_effect(bus, i)
			break
