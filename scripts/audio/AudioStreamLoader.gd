extends RefCounted
## One runtime loader for filesystem paths (including files outside res://).
const EXTENSIONS = ["mp3", "ogg", "wav", "flac"]
const FILE_FILTER = "*.mp3, *.ogg, *.wav, *.flac ; Audio files"
static var last_error: String = ""

static func supports(path: String) -> bool:
	return path.get_extension().to_lower() in EXTENSIONS

static func load_file(path: String) -> AudioStream:
	last_error = ""
	if not supports(path):
		last_error = "Choose an MP3, OGG, WAV or FLAC file."
		return null
	if not FileAccess.file_exists(path):
		last_error = "File not found: " + path.get_file()
		return null
	var stream: AudioStream
	match path.get_extension().to_lower():
		"mp3": stream = AudioStreamMP3.load_from_file(path)
		"ogg": stream = AudioStreamOggVorbis.load_from_file(path)
		"wav": stream = AudioStreamWAV.load_from_file(path)
		"flac":
			# Dynamic construction keeps the app usable if the native DLL is missing.
			# AudioStreamFLAC exposes data + is_valid(), not load_from_file().
			if not ClassDB.class_exists(&"AudioStreamFLAC"):
				last_error = "FLAC support is unavailable. Install addons/xiph_audio and restart VizMP."
				return null
			var file := FileAccess.open(path, FileAccess.READ)
			if file != null:
				var bytes := file.get_buffer(file.get_length())
				if not bytes.is_empty() and bytes.size() == file.get_length():
					stream = ClassDB.instantiate(&"AudioStreamFLAC") as AudioStream
					if stream != null:
						stream.set("data", bytes)
						if not stream.call("is_valid"):
							stream = null
	if stream == null:
		last_error = "Could not decode: " + path.get_file()
	return stream
