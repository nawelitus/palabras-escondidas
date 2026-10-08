extends SceneTree
## Headless sanity check for synthesized sounds: not empty, not clipping, sane length.
## Run: godot --headless --path . -s tools/test_sound.gd

const MIN_PEAK := 2000
const MAX_PEAK := 32000
const MAX_SECONDS := 1.5


func _initialize() -> void:
	# Scripts run with -s compile before autoloads exist, so look it up by path.
	await process_frame  # let the autoload finish its _ready (audio players)
	var feedback: Node = root.get_node("Feedback")
	# Trigger every sound once so the lazy cache is filled.
	for size in [1, 2, 3, 6, 12]:
		feedback.tile_step(size)
	for length in [3, 5, 8]:
		feedback.word_ok(length)
	feedback.word_bad()
	feedback.word_repeat()
	feedback.tick()
	feedback.round_end(false)
	feedback.round_end(true)
	feedback.click()

	var failures := 0
	var keys: Array = feedback._cache.keys()
	keys.sort()
	for key: String in keys:
		var stream: AudioStreamWAV = feedback._cache[key]
		var samples := stream.data.size() / 2
		var peak := 0
		for i in samples:
			peak = maxi(peak, absi(stream.data.decode_s16(i * 2)))
		var seconds := float(samples) / stream.mix_rate
		var ok := samples > 0 and peak >= MIN_PEAK and peak <= MAX_PEAK and seconds <= MAX_SECONDS
		if not ok:
			failures += 1
		print("%-12s samples=%6d seconds=%.2f peak=%5d %s" % [key, samples, seconds, peak, "ok" if ok else "FAIL"])
	print("sounds=%d failures=%d" % [keys.size(), failures])
	quit(1 if failures > 0 else 0)
