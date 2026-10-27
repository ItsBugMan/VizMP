extends SceneTree
## External-process fixture: emits different frequencies in left/right channels.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await create_timer(0.8).timeout
	var data := PackedByteArray()
	data.resize(44100 * 4 * 4)
	for frame in range(44100 * 4):
		data.encode_s16(frame * 4, int(sin(TAU * 220.0 * frame / 44100.0) * 3000.0))
		data.encode_s16(frame * 4 + 2, int(sin(TAU * 880.0 * frame / 44100.0) * 3000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = true
	stream.mix_rate = 44100
	stream.data = data
	var player := AudioStreamPlayer.new()
	root.add_child(player)
	player.stream = stream
	player.play()
	await create_timer(4.1).timeout
	player.stop()
	player.queue_free()
	await process_frame
	quit()
