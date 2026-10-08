class_name ToneSynth
extends RefCounted
## Builds short 16-bit mono sounds in memory from a list of notes, so the game
## needs no audio files. Swap these for recorded assets later without touching callers.

const MIX_RATE := 22050
const ATTACK_SECONDS := 0.004
## Higher = the note dies away faster inside its duration.
const DECAY := 4.0

enum Wave { SOFT, BUZZ }


## One note. freq_end >= 0 makes the pitch glide from freq to freq_end.
static func note(freq: float, start: float, duration: float, volume: float = 0.4,
		wave: Wave = Wave.SOFT, freq_end: float = -1.0) -> Dictionary:
	return {
		"freq": freq, "start": start, "dur": duration, "vol": volume,
		"wave": wave, "freq_end": freq_end,
	}


static func render(notes: Array[Dictionary]) -> AudioStreamWAV:
	var total := 0.0
	for n in notes:
		total = maxf(total, n["start"] + n["dur"])
	var count := int(total * MIX_RATE) + 1
	var mix := PackedFloat32Array()
	mix.resize(count)
	for n in notes:
		_mix_note(mix, n)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		bytes.encode_s16(i * 2, int(clampf(mix[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	return stream


static func _mix_note(mix: PackedFloat32Array, n: Dictionary) -> void:
	var first := int(n["start"] * MIX_RATE)
	var length := int(n["dur"] * MIX_RATE)
	var freq_start: float = n["freq"]
	var freq_end: float = n["freq_end"] if n["freq_end"] >= 0.0 else freq_start
	var volume: float = n["vol"]
	var buzz: bool = n["wave"] == Wave.BUZZ
	var phase := 0.0
	for i in length:
		var t := float(i) / length
		var freq := lerpf(freq_start, freq_end, t)
		phase += TAU * freq / MIX_RATE
		var sample: float
		if buzz:
			sample = (sin(phase) + sin(3.0 * phase) / 3.0 + sin(5.0 * phase) / 5.0) * 0.8
		else:
			sample = sin(phase) + 0.25 * sin(2.0 * phase)
		var envelope := minf(float(i) / (ATTACK_SECONDS * MIX_RATE), 1.0) * exp(-DECAY * t)
		var index := first + i
		if index < mix.size():
			mix[index] += sample * envelope * volume
