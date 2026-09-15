class_name SoundBank
extends RefCounted
## Synthesised placeholder sounds, so every event has a sound before any real
## file exists. Each generator returns an AudioStreamWAV built from a short
## float envelope; nothing here is meant to be pretty, only readable.
##
## Real sounds replace these by dropping a file with the same name into
## `assets/audio/sfx/` (see Sfx).

const RATE := 22050


## Builds the sound for `name`, or null when there is no generator for it.
static func build(name: StringName) -> AudioStreamWAV:
	match name:
		&"jump": return _sweep(0.18, 300.0, 700.0, 0.5)
		&"double_jump": return _sweep(0.2, 500.0, 1100.0, 0.45)
		&"land": return _noise(0.08, 0.35, 900.0)
		&"attack": return _noise(0.12, 0.45, 3000.0, true)
		&"hit": return _mix([_sweep(0.1, 220.0, 90.0, 0.7), _noise(0.06, 0.4, 2500.0)])
		&"hurt": return _sweep(0.25, 400.0, 150.0, 0.6)
		&"enemy_die": return _mix([_sweep(0.3, 600.0, 120.0, 0.5), _noise(0.15, 0.3, 1500.0)])
		&"star": return _arpeggio([880.0, 1108.7, 1318.5, 1760.0], 0.07, 0.45)
		&"checkpoint": return _arpeggio([523.3, 659.3, 784.0], 0.1, 0.4)
		&"unlock": return _arpeggio([523.3, 659.3, 784.0, 1046.5, 1318.5], 0.11, 0.45)
		&"fanfare": return _arpeggio([523.3, 523.3, 523.3, 659.3, 784.0, 1046.5], 0.14, 0.5)
		&"portal": return _sweep(0.6, 200.0, 1400.0, 0.4)
		&"turbo": return _mix([_sweep(0.5, 150.0, 900.0, 0.5), _noise(0.5, 0.25, 4000.0)])
		&"ui": return _sweep(0.05, 900.0, 1200.0, 0.3)
		# Two-tone car horn: a fifth, held.
		&"horn": return _mix([_sweep(0.45, 440.0, 440.0, 0.45), _sweep(0.45, 660.0, 660.0, 0.35)])
		&"engine": return _engine_loop()
	return null


## Frequency glide with a fast attack and exponential decay.
static func _sweep(duration: float, from_hz: float, to_hz: float, volume: float) -> AudioStreamWAV:
	var count := int(duration * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / count
		var hz := lerpf(from_hz, to_hz, t)
		phase += TAU * hz / RATE
		var env := minf(t * 40.0, 1.0) * pow(1.0 - t, 1.5)
		samples[i] = (sin(phase) * 0.7 + sin(phase * 2.0) * 0.3) * env * volume
	return _wav(samples, false)


## Filtered noise burst (one-pole low-pass at roughly `cutoff` Hz).
static func _noise(duration: float, volume: float, cutoff: float, sharp := false) -> AudioStreamWAV:
	var count := int(duration * RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var alpha := clampf(cutoff / RATE * TAU, 0.0, 1.0)
	var low := 0.0
	for i in count:
		var t := float(i) / count
		low += (rng.randf_range(-1.0, 1.0) - low) * alpha
		var env := pow(1.0 - t, 3.0 if sharp else 1.5)
		samples[i] = low * env * volume
	return _wav(samples, false)


## Short notes in a row, each a plucked sine.
static func _arpeggio(notes: Array, note_length: float, volume: float) -> AudioStreamWAV:
	var per_note := int(note_length * RATE)
	var tail := int(0.25 * RATE)
	var samples := PackedFloat32Array()
	samples.resize(per_note * notes.size() + tail)
	for n in notes.size():
		var hz: float = notes[n]
		var start := n * per_note
		var length := per_note + tail
		for i in length:
			var t := float(i) / length
			var env := minf(i / 200.0, 1.0) * pow(1.0 - t, 2.0)
			var v := (sin(TAU * hz * i / RATE) * 0.6 + sin(TAU * hz * 2.0 * i / RATE) * 0.2) * env * volume
			samples[start + i] += v
	return _wav(samples, false)


## Looping low buzz; the player pitches it with the speed.
static func _engine_loop() -> AudioStreamWAV:
	var hz := 55.0
	var cycles := 20
	var count := int(cycles * RATE / hz)
	var samples := PackedFloat32Array()
	samples.resize(count)
	for i in count:
		var t := float(i) / RATE
		var saw := 2.0 * fmod(t * hz, 1.0) - 1.0
		var square := 1.0 if fmod(t * hz * 0.5, 1.0) < 0.5 else -1.0
		samples[i] = (saw * 0.35 + square * 0.15 + sin(TAU * hz * 2.0 * t) * 0.2) * 0.35
	return _wav(samples, true)


static func _mix(parts: Array[AudioStreamWAV]) -> AudioStreamWAV:
	var longest := 0
	for p in parts:
		longest = maxi(longest, p.data.size() / 2)
	var samples := PackedFloat32Array()
	samples.resize(longest)
	for p in parts:
		var data := p.data
		for i in data.size() / 2:
			samples[i] += data.decode_s16(i * 2) / 32767.0
	return _wav(samples, false)


static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = samples.size()
	return stream
