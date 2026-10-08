extends SceneTree
## Lists the words of a board with one tracing path each, longest first.
## Run: godot --headless --path . --quit-after 600 -s tools/solve_board.gd -- e,s,c,o,d,i,d,n,a,s,t,e,l,o,r,a [max_words]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var board := PackedStringArray(args[0].split(","))
	var limit := int(args[1]) if args.size() > 1 else 40
	var dictionary := WordDictionary.new()
	dictionary.load_from_file("res://data/words_es.txt")
	var solutions := BoardSolver.solve(board, dictionary)
	var words: Array = solutions.keys()
	words.sort_custom(func(a: String, b: String) -> bool:
		return a.length() > b.length() or (a.length() == b.length() and a < b))
	print("words=%d" % words.size())
	for i in mini(limit, words.size()):
		print("%s %s" % [words[i], solutions[words[i]]])
	quit()
