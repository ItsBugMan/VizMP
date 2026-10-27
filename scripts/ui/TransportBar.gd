extends VBoxContainer
## Commit one seek on release; slider updates never chase the user's pointer.
signal previous_requested
signal next_requested
var player: AudioStreamPlayer
var slider: HSlider
var _time: Label
var _dragging := false
var _syncing := false
var _buttons: Array[Button] = []
var _seek_guard := 0.0
var _last_position := 0.0

func _ready() -> void:
	var buttons := HBoxContainer.new()
	add_child(buttons)
	for text in ["Previous", "Play", "Pause", "Next"]:
		var button := Button.new()
		button.text = text
		buttons.add_child(button)
		_buttons.append(button)
	_buttons[0].pressed.connect(func() -> void: previous_requested.emit())
	_buttons[1].pressed.connect(func() -> void:
		if player.stream == null: return
		if not player.playing: player.play()
		player.stream_paused = false)
	_buttons[2].pressed.connect(func() -> void: player.stream_paused = true)
	_buttons[3].pressed.connect(func() -> void: next_requested.emit())
	slider = HSlider.new()
	slider.step = 0.01
	slider.custom_minimum_size.y = 22
	slider.drag_started.connect(func() -> void: _dragging = true)
	slider.drag_ended.connect(func(changed: bool) -> void:
		_dragging = false
		if changed: seek_to(slider.value))
	# Keyboard/accessibility adjustment also seeks, with no feedback loop.
	slider.value_changed.connect(func(value: float) -> void:
		if not _dragging and not _syncing: seek_to(value))
	add_child(slider)
	_time = Label.new()
	add_child(_time)

func seek_to(seconds: float) -> void:
	if player.stream == null or AudioLoopbackManager.mode != AudioLoopbackManager.Mode.FILE: return
	var position := clampf(seconds, 0.0, maxf(0.0, player.stream.get_length() - 0.001))
	var paused := player.stream_paused
	if player.playing: player.seek(position)
	else: player.play(position)
	player.stream_paused = paused
	AudioAnalyzer.reset_after_seek()
	StereoPCM.reset()
	_last_position = position
	_seek_guard = 0.1

func _process(delta: float) -> void:
	if player == null: return
	var live := AudioLoopbackManager.mode == AudioLoopbackManager.Mode.DESKTOP
	var available := not live and player.stream != null
	for button in _buttons: button.disabled = not available and button != _buttons[0] and button != _buttons[3]
	_buttons[0].disabled = live
	_buttons[3].disabled = live
	slider.editable = available
	if not available:
		_time.text = "Live desktop audio" if live else "No track loaded"
		return
	_syncing = true
	slider.max_value = maxf(0.01, player.stream.get_length())
	_syncing = false
	_seek_guard = maxf(0.0, _seek_guard - delta)
	var position := player.get_playback_position()
	if player.playing and not player.stream_paused:
		position += AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
	if _seek_guard > 0.0: position = _last_position
	position = clampf(position, 0.0, slider.max_value)
	if not _dragging: slider.set_value_no_signal(position)
	_time.text = "%s / %s" % [_stamp(slider.value), _stamp(slider.max_value)]

func _stamp(seconds: float) -> String:
	var whole := int(seconds)
	return "%d:%02d" % [whole / 60, whole % 60]
