extends Node
## Autoload: sound effects and vibration for game events.
## Sounds are synthesized on first use and cached. Both channels can be turned
## off from GameSettings.

const PLAYER_COUNT := 8
## Vibration tuning. The scale shortens every pulse; the amplitude (0..1) only has
## an effect on phones with amplitude control. Raise both for a stronger feel.
const HAPTIC_SCALE := 0.5
const HAPTIC_AMPLITUDE := 0.4
const HAPTIC_MIN_MS := 5
const BASE_FREQ := 392.0  # G4
## Semitone offsets of a major pentatonic scale: any chain of tiles sounds pleasant.
const PENTATONIC: Array[int] = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24, 26]
const NOTE_C5 := 523.25
const NOTE_E5 := 659.25
const NOTE_G5 := 783.99
const NOTE_B5 := 987.77
const NOTE_C6 := 1046.5

var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _cache := {}


func _ready() -> void:
	for i in PLAYER_COUNT:
		var player := AudioStreamPlayer.new()
		player.volume_db = -4.0
		add_child(player)
		_players.append(player)


## Pitch climbs with every tile chained (and falls when the last one is undone).
func tile_step(path_size: int) -> void:
	var step := clampi(path_size - 1, 0, PENTATONIC.size() - 1)
	var freq := BASE_FREQ * pow(2.0, PENTATONIC[step] / 12.0)
	_play("select_%d" % step, func() -> Array[Dictionary]:
		return [ToneSynth.note(freq, 0.0, 0.09, 0.45)])
	_vibrate(12)


func word_ok(word_length: int) -> void:
	if word_length <= 4:
		_play("ok_small", func() -> Array[Dictionary]:
			return [
				ToneSynth.note(NOTE_E5, 0.0, 0.22, 0.4),
				ToneSynth.note(NOTE_B5, 0.07, 0.25, 0.4)])
		_vibrate(25)
	elif word_length <= 6:
		_play("ok_mid", func() -> Array[Dictionary]:
			return [
				ToneSynth.note(NOTE_C5, 0.0, 0.25, 0.38),
				ToneSynth.note(NOTE_E5, 0.07, 0.25, 0.38),
				ToneSynth.note(NOTE_G5, 0.14, 0.3, 0.4)])
		_vibrate(40)
	else:
		_play("ok_big", func() -> Array[Dictionary]:
			return [
				ToneSynth.note(NOTE_C5, 0.0, 0.3, 0.34),
				ToneSynth.note(NOTE_E5, 0.07, 0.3, 0.34),
				ToneSynth.note(NOTE_G5, 0.14, 0.3, 0.36),
				ToneSynth.note(NOTE_C6, 0.21, 0.45, 0.4),
				ToneSynth.note(NOTE_C6 * 2.0, 0.3, 0.3, 0.2)])
		_vibrate(70)


func word_bad() -> void:
	_play("bad", func() -> Array[Dictionary]:
		return [ToneSynth.note(180.0, 0.0, 0.22, 0.35, ToneSynth.Wave.BUZZ, 110.0)])
	_vibrate(55)


func word_repeat() -> void:
	_play("repeat", func() -> Array[Dictionary]:
		return [
			ToneSynth.note(300.0, 0.0, 0.07, 0.3),
			ToneSynth.note(300.0, 0.09, 0.07, 0.3)])
	_vibrate(20)


## One per second during the last seconds of the round.
func tick() -> void:
	_play("tick", func() -> Array[Dictionary]:
		return [ToneSynth.note(880.0, 0.0, 0.06, 0.35)])
	_vibrate(15)


func round_end(new_record: bool) -> void:
	if new_record:
		_play("end_record", func() -> Array[Dictionary]:
			return [
				ToneSynth.note(NOTE_C5, 0.0, 0.3, 0.3),
				ToneSynth.note(NOTE_E5, 0.12, 0.3, 0.3),
				ToneSynth.note(NOTE_G5, 0.24, 0.3, 0.3),
				# Final chord: kept quiet per note so the sum does not clip.
				ToneSynth.note(NOTE_C6, 0.36, 0.7, 0.3),
				ToneSynth.note(NOTE_E5, 0.36, 0.7, 0.14),
				ToneSynth.note(NOTE_G5, 0.36, 0.7, 0.14)])
		_vibrate(220)
	else:
		_play("end", func() -> Array[Dictionary]:
			return [
				ToneSynth.note(NOTE_G5, 0.0, 0.3, 0.35),
				ToneSynth.note(NOTE_E5, 0.14, 0.3, 0.35),
				ToneSynth.note(NOTE_C5, 0.28, 0.3, 0.35),
				ToneSynth.note(BASE_FREQ, 0.42, 0.6, 0.38)])
		_vibrate(150)


func click() -> void:
	_play("click", func() -> Array[Dictionary]:
		return [ToneSynth.note(700.0, 0.0, 0.05, 0.3)])


func _play(key: String, build_notes: Callable) -> void:
	if not GameSettings.sound_enabled:
		return
	if not _cache.has(key):
		var notes: Array[Dictionary] = build_notes.call()
		_cache[key] = ToneSynth.render(notes)
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = _cache[key]
	player.play()


func _vibrate(milliseconds: int) -> void:
	if GameSettings.haptics_enabled:
		var scaled := maxi(int(milliseconds * HAPTIC_SCALE), HAPTIC_MIN_MS)
		Input.vibrate_handheld(scaled, HAPTIC_AMPLITUDE)
