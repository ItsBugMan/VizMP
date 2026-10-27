extends Node
## One global publisher for every CanvasItem/Spatial shader and window.
## Globals MUST be declared in Project Settings before shaders are compiled.
## Global uniform arrays are not used: 64 bins travel in a 64x1 R8 texture.

var _pixels := PackedByteArray()
var _image: Image
var _texture: ImageTexture
var _beat_serial: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pixels.resize(AudioAnalyzer.BIN_COUNT)
	_image = Image.create_from_data(AudioAnalyzer.BIN_COUNT, 1, false, Image.FORMAT_R8, _pixels)
	_texture = ImageTexture.create_from_image(_image)
	RenderingServer.global_shader_parameter_set(&"audio_spectrum", _texture)
	AudioAnalyzer.spectrum_updated.connect(_publish_spectrum)
	AudioAnalyzer.beat_detected.connect(_publish_beat)
	RenderingServer.global_shader_parameter_set(&"audio_event", Vector2.ZERO)
	_publish_spectrum()

func _publish_beat(strength: float) -> void:
	# A serial lets fixed-step GPU simulations observe onsets between ticks.
	# Integers through 65535 are represented exactly in float32.
	_beat_serial = (_beat_serial + 1) % 65536
	RenderingServer.global_shader_parameter_set(&"audio_event", Vector2(_beat_serial, strength))

func _publish_spectrum() -> void:
	# 64 bytes per upload; preserve the ImageTexture RID by calling update().
	for i in range(AudioAnalyzer.BIN_COUNT):
		_pixels[i] = int(round(clampf(AudioAnalyzer.spectrum[i], 0.0, 1.0) * 255.0))
	_image.set_data(AudioAnalyzer.BIN_COUNT, 1, false, Image.FORMAT_R8, _pixels)
	_texture.update(_image)

func _process(_delta: float) -> void:
	# Pulse decays every rendered frame, independently of the analysis cadence.
	# vec4 packing reduces RenderingServer calls. Never read globals back here:
	# global_shader_parameter_get() can synchronize the render thread.
	RenderingServer.global_shader_parameter_set(&"audio_bands", Vector4(
		AudioAnalyzer.bass, AudioAnalyzer.mid, AudioAnalyzer.treble, AudioAnalyzer.volume))
	RenderingServer.global_shader_parameter_set(&"audio_details", Vector4(
		AudioAnalyzer.sub_bass, AudioAnalyzer.highs, AudioAnalyzer.beat_pulse, 0.0))
