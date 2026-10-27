extends RefCounted
## Bounded, dependency-free ID3v2.3/2.4, ID3v1, Vorbis comments and RIFF INFO reader.
## Unsupported/compressed ID3 frames are skipped; malformed tags retain filename fallback.
const MAX_TAG := 16 * 1024 * 1024

static func read_track(path: String, include_cover: bool = true) -> Dictionary:
	var result := {"title": path.get_file().get_basename(), "artist": "", "album": "", "cover": null}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return result
	if path.get_extension().to_lower() == "wav":
		_riff_file(f, result, include_cover)
		return result
	var head := f.get_buffer(10)
	var budget := mini(f.get_length(), MAX_TAG)
	if path.get_extension().to_lower() == "mp3":
		budget = 10
		if head.size() == 10 and head.slice(0, 3).get_string_from_ascii() == "ID3":
			budget = mini(f.get_length(), mini(MAX_TAG, 10 + _size(head, 6, true)))

	f.seek(0)
	var data := f.get_buffer(budget)
	match path.get_extension().to_lower():
		"mp3":
			_id3(data, result, include_cover)
			if f.get_length() >= 128:
				f.seek(f.get_length() - 128)
				var tail := f.get_buffer(128)
				if tail.slice(0, 3).get_string_from_ascii() == "TAG":
					for item in [["title", 3], ["artist", 33], ["album", 63]]:
						if result[item[0]] == "" or (item[0] == "title" and result.title == path.get_file().get_basename()):
							var text := tail.slice(item[1], item[1] + 30).get_string_from_ascii().strip_edges()
							if not text.is_empty(): result[item[0]] = text
		"ogg": _ogg(data, result, include_cover)
		"wav": _riff(data, result)
	return result

static func _size(data: PackedByteArray, at: int, sync: bool = false) -> int:
	if at < 0 or at + 4 > data.size(): return 0
	var n := 0
	for i in range(4): n = (n << (7 if sync else 8)) | (data[at + i] & (127 if sync else 255))
	return n

static func _text(data: PackedByteArray) -> String:
	if data.is_empty(): return ""
	match data[0]:
		1, 2:
			var little := data[0] == 1 and data.size() > 2 and data[1] == 255
			var start := 3 if data.size() > 2 and ((data[1] == 255 and data[2] == 254) or (data[1] == 254 and data[2] == 255)) else 1
			var units := PackedByteArray()
			for i in range(start, data.size() - 1, 2):
				units.append(data[i] if little else data[i + 1])
				units.append(data[i + 1] if little else data[i])
			return units.get_string_from_utf16().strip_edges()
		0:
			var s := ""
			for b in data.slice(1):
				if b == 0: break
				s += String.chr(b)
			return s.strip_edges()
		_: return data.slice(1).get_string_from_utf8().strip_edges()

static func _id3(d: PackedByteArray, out: Dictionary, cover: bool) -> void:
	if d.size() < 10 or d.slice(0, 3).get_string_from_ascii() != "ID3" or not d[3] in [3, 4]: return
	var version := d[3]
	# Global unsynchronisation is uncommon; don't misinterpret its frame boundaries.
	if d[5] & 128: return
	var end := mini(d.size(), 10 + _size(d, 6, true))
	var pos := 10
	if d[5] & 64:
		pos += _size(d, pos, version == 4) + (4 if version == 3 else 0)
	while pos + 10 <= end:
		var id := d.slice(pos, pos + 4).get_string_from_ascii()
		var count := _size(d, pos + 4, version == 4)
		var flags := d[pos + 9]
		pos += 10
		if count <= 0 or count > end - pos: break
		var frame := d.slice(pos, pos + count)
		pos += count
		if flags != 0: continue
		if id in ["TIT2", "TPE1", "TALB"]:
			var key: String = {"TIT2": "title", "TPE1": "artist", "TALB": "album"}[id]
			var value := _text(frame)
			if not value.is_empty(): out[key] = value
		elif id == "APIC" and cover and frame.size() > 4:
			var at := 1
			while at < frame.size() and frame[at] != 0: at += 1
			at += 2 # MIME terminator and picture type.
			var step := 2 if frame[0] in [1, 2] else 1
			while at + step <= frame.size():
				if frame[at] == 0 and (step == 1 or frame[at + 1] == 0):
					at += step
					break
				at += step
			out.cover = _image(frame.slice(at))

static func _image(bytes: PackedByteArray) -> Texture2D:
	if bytes.size() < 24 or bytes.size() > 8 * 1024 * 1024: return null
	var image := Image.new()
	var error := image.load_png_from_buffer(bytes) if bytes[0] == 137 else image.load_jpg_from_buffer(bytes)
	if error != OK: return null
	if image.get_width() > 1024 or image.get_height() > 1024: image.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)

static func _comments(d: PackedByteArray, out: Dictionary, cover: bool) -> void:
	if d.size() < 8: return
	var at := 4 + int(d.decode_u32(0))
	if at + 4 > d.size(): return
	var count := mini(int(d.decode_u32(at)), 4096)
	at += 4
	for i in range(count):
		if at + 4 > d.size(): break
		var length := int(d.decode_u32(at))
		at += 4
		if length > d.size() - at: break
		var text := d.slice(at, at + length).get_string_from_utf8()
		at += length
		var split := text.find("=")
		if split < 0: continue
		var key := text.left(split).to_lower()
		var value := text.substr(split + 1)
		if key in ["title", "artist", "album"] and not value.is_empty(): out[key] = value
		elif key == "metadata_block_picture" and cover:
			var pic := Marshalls.base64_to_raw(value)
			if pic.size() < 12: continue
			var offset := 8 + _size(pic, 4)
			if offset + 4 > pic.size(): continue
			offset += 4 + _size(pic, offset)
			offset += 16 # Dimensions, depth and palette.
			if offset + 4 > pic.size(): continue
			var size := _size(pic, offset)
			offset += 4
			if size <= pic.size() - offset: out.cover = _image(pic.slice(offset, offset + size))

static func _ogg(d: PackedByteArray, out: Dictionary, cover: bool) -> void:
	var at := 0
	var packet := PackedByteArray()
	var serial := -1
	while at + 27 <= d.size():
		if d.slice(at, at + 4).get_string_from_ascii() != "OggS": break
		if serial < 0: serial = d.decode_u32(at + 14)
		var segments := int(d[at + 26])
		var body := at + 27 + segments
		if body > d.size(): break
		var selected := d.decode_u32(at + 14) == serial
		for i in range(segments):
			var length := int(d[at + 27 + i])
			if body + length > d.size(): return
			if selected: packet.append_array(d.slice(body, body + length))
			body += length
			if selected and length < 255:
				if packet.size() > 7 and packet[0] == 3 and packet.slice(1, 7).get_string_from_ascii() == "vorbis":
					_comments(packet.slice(7), out, cover)
					return
				packet.clear()
		at = body

static func _riff(d: PackedByteArray, out: Dictionary) -> void:
	if d.size() < 12 or d.slice(0, 4).get_string_from_ascii() != "RIFF": return
	var at := 12
	while at + 8 <= d.size():
		var id := d.slice(at, at + 4).get_string_from_ascii()
		var length := int(d.decode_u32(at + 4))
		at += 8
		if length > d.size() - at: break
		if id == "LIST" and length >= 4 and d.slice(at, at + 4).get_string_from_ascii() == "INFO":
			var pos := at + 4
			while pos + 8 <= at + length:
				var key := d.slice(pos, pos + 4).get_string_from_ascii()
				var size := int(d.decode_u32(pos + 4))
				pos += 8
				if size > at + length - pos: break
				if key in ["INAM", "IART", "IPRD"]:
					out[{"INAM": "title", "IART": "artist", "IPRD": "album"}[key]] = d.slice(pos, pos + size).get_string_from_utf8().strip_edges()
				pos += size + (size & 1)
		at += length + (length & 1)

static func _riff_file(f: FileAccess, out: Dictionary, cover: bool) -> void:
	var header := f.get_buffer(12)
	if header.size() < 12 or header.slice(0, 4).get_string_from_ascii() != "RIFF" or header.slice(8, 12).get_string_from_ascii() != "WAVE": return
	var limit := mini(f.get_length(), int(header.decode_u32(4)) + 8)
	var pos := 12
	# Seek over PCM chunks: tags after multi-gigabyte audio remain inexpensive.
	for i in range(4096):
		if pos + 8 > limit: break
		f.seek(pos)
		var chunk := f.get_buffer(8)
		var id := chunk.slice(0, 4).get_string_from_ascii()
		var size := int(chunk.decode_u32(4))
		pos += 8
		if size > limit - pos: break
		if size <= MAX_TAG:
			if id == "LIST":
				var payload := header.duplicate()
				payload.append_array(chunk)
				payload.append_array(f.get_buffer(size))
				_riff(payload, out)
			elif id.to_lower() == "id3 ": _id3(f.get_buffer(size), out, cover)
		pos += size + (size & 1)
