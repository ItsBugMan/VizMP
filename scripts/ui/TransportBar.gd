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
var volume_slider: HSlider
var mute_button: CheckBox
var _volume_label: Label
var _volume_title: Label
var _desktop_volume_note: Label
var _button_row: HBoxContainer
var _volume_row: HBoxContainer
var _compact_row: HBoxContainer
var _illustrated: bool = false

func _ready() -> void:
	var buttons := HBoxContainer.new()
	_button_row = buttons
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
	SkinManager.skin_changed.connect(_refresh_glyphs)
	_refresh_glyphs()
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
	_time.theme_type_variation = &"LCDReadout"
	add_child(_time)
	_build_volume()
	_compact_row = HBoxContainer.new()
	add_child(_compact_row)
	SkinManager.skin_changed.connect(_refresh_layout)
	_refresh_layout.call_deferred()

func _refresh_glyphs() -> void:
	var labels: Array = ["Previous", "Play", "Pause", "Next"]
	var glyphs: Array = SkinManager.chrome.get("glyphs", labels)
	for i in range(_buttons.size()):
		_buttons[i].text = glyphs[i]
		_buttons[i].tooltip_text = labels[i]

func _build_volume() -> void:
	_volume_title = Label.new()
	_volume_title.text = "File volume"
	add_child(_volume_title)
	var row := HBoxContainer.new()
	_volume_row = row
	add_child(row)
	mute_button = CheckBox.new()
	mute_button.text = "Mute"
	mute_button.toggled.connect(AudioOutput.set_muted)
	row.add_child(mute_button)
	volume_slider = HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 100.0
	volume_slider.step = 1.0
	volume_slider.custom_minimum_size = Vector2(80, 24)
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.value_changed.connect(AudioOutput.set_volume_percent)
	row.add_child(volume_slider)
	_volume_label = Label.new()
	_volume_label.custom_minimum_size.x = 45
	_volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_volume_label)
	_desktop_volume_note = Label.new()
	_desktop_volume_note.text = "Desktop volume: use Windows."
	_desktop_volume_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_desktop_volume_note)
	AudioOutput.changed.connect(_sync_volume)
	AudioLoopbackManager.mode_changed.connect(_on_volume_mode_changed)
	_sync_volume()

func _on_volume_mode_changed(_mode: int) -> void:
	_sync_volume()

func _sync_volume() -> void:
	var live: bool = AudioLoopbackManager.mode == AudioLoopbackManager.Mode.DESKTOP
	volume_slider.set_value_no_signal(AudioOutput.get_volume_percent())
	mute_button.set_pressed_no_signal(AudioOutput.muted)
	volume_slider.editable = not live
	mute_button.disabled = live
	_volume_title.text = "File volume (saved)" if live else "File volume"
	_volume_title.visible = not _illustrated
	_desktop_volume_note.visible = live
	var silent: bool = AudioOutput.muted or AudioOutput.volume_linear <= 0.0
	_volume_label.text = "%d%%" % roundi(AudioOutput.get_volume_percent())
	var detail: String = "Silent" if AudioOutput.volume_linear <= 0.0 else "%+.1f dB" % AudioOutput.get_volume_db()
	var tip: String = "File playback: %s (%s)%s" % [_volume_label.text, detail, " — muted" if AudioOutput.muted else ""]
	if live:
		tip = "Saved file volume. Desktop capture is unchanged; adjust other apps in Windows."
	volume_slider.tooltip_text = tip
	mute_button.tooltip_text = tip if live else "Mute file playback; keep the selected volume."
	_volume_label.tooltip_text = tip
	_volume_label.modulate.a = 0.5 if silent or live else 1.0

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

func _refresh_layout() -> void:
	_illustrated = SkinManager.chrome.has("layout")
	if _compact_row == null: return
	_compact_row.visible = _illustrated
	_volume_title.visible = not _illustrated
	var target: Node = _compact_row if _illustrated else self
	if _button_row.get_parent() != target: _button_row.reparent(target, false)
	if _volume_row.get_parent() != target: _volume_row.reparent(target, false)
	_volume_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _illustrated:
		move_child(_compact_row, 0)
		move_child(slider, 1)
		move_child(_time, 2)
		_time.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	else:
		move_child(_button_row, 0)
		move_child(slider, 1)
		move_child(_time, 2)
		move_child(_volume_title, 3)
		move_child(_volume_row, 4)
		_time.remove_theme_stylebox_override("normal")
	for button in _buttons:
		button.custom_minimum_size = Vector2(48, 40) if _illustrated else Vector2.ZERO
