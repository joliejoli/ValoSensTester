static func _make_tone(freq: float, duration: float, volume: float) -> AudioStreamWAV:
	var rate := 22050
	var frames := int(duration * rate)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var t := float(i) / rate
		var env := 1.0 - t / duration
		var v := sin(TAU * freq * t) * volume * env
		var s := int(clampf(v, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, s)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream

static func shot() -> AudioStreamWAV:
	return _make_tone(950.0, 0.05, 0.35)

static func hit() -> AudioStreamWAV:
	return _make_tone(520.0, 0.09, 0.5)

static func miss() -> AudioStreamWAV:
	return _make_tone(190.0, 0.07, 0.3)
