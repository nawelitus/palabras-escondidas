extends SceneTree
## Headless sanity check for dictionary, generator and solver.
## Run: godot --headless --path . -s tools/test_board.gd

const BOARDS := 1000


func _init() -> void:
	var dictionary := WordDictionary.new()
	var t0 := Time.get_ticks_msec()
	var ok := dictionary.load_from_file("res://data/words_es.txt")
	print("load: ok=%s words=%d in %d ms" % [ok, dictionary.size(), Time.get_ticks_msec() - t0])
	print("sorted: %s" % dictionary.is_sorted())
	for word in ["casas", "corrieron", "cañon", "veni", "zzz", "ca", "caso"]:
		print("has_word(%s)=%s has_prefix=%s" % [word, dictionary.has_word(word), dictionary.has_prefix(word)])

	var generator := BoardGenerator.new(12345)
	var counts: Array[int] = []
	var vowel_total := 0
	var kw_boards := 0
	var t1 := Time.get_ticks_msec()
	for i in BOARDS:
		var board := generator.generate_playable(dictionary)
		counts.append(BoardSolver.solve(board, dictionary).size())
		var has_kw := false
		for tile in board:
			if tile in BoardGenerator.VOWELS:
				vowel_total += 1
			if tile == "k" or tile == "w":
				has_kw = true
		if has_kw:
			kw_boards += 1
		if i == 0:
			print("sample board: %s" % ", ".join(board))
	var elapsed := Time.get_ticks_msec() - t1
	counts.sort()
	var sum := 0
	for c in counts:
		sum += c
	print("boards=%d solve avg=%.1f ms" % [BOARDS, float(elapsed) / BOARDS])
	print("words/board min=%d p10=%d median=%d p90=%d max=%d avg=%.1f" % [
		counts[0], counts[BOARDS / 10], counts[BOARDS / 2], counts[BOARDS * 9 / 10], counts[-1],
		float(sum) / BOARDS])
	print("avg vowels/board=%.2f" % (float(vowel_total) / BOARDS))
	print("boards with k or w: %d of %d" % [kw_boards, BOARDS])
	quit()
