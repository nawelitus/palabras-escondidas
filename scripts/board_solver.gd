class_name BoardSolver
extends RefCounted
## Finds every dictionary word that can be traced on a board.

const MIN_WORD_LENGTH := 3


## Returns {word: Array[int]} with the tile indices of one way to trace each word.
static func solve(board: PackedStringArray, dictionary: WordDictionary, size: int = 4) -> Dictionary:
	var found := {}
	var visited := PackedByteArray()
	visited.resize(board.size())
	var path: Array[int] = []
	for start in board.size():
		_search(board, dictionary, size, start, "", path, visited, found)
	return found


static func _search(
	board: PackedStringArray,
	dictionary: WordDictionary,
	size: int,
	index: int,
	prefix: String,
	path: Array[int],
	visited: PackedByteArray,
	found: Dictionary
) -> void:
	var word := prefix + board[index]
	if not dictionary.has_prefix(word):
		return
	visited[index] = 1
	path.append(index)
	if word.length() >= MIN_WORD_LENGTH and not found.has(word) and dictionary.has_word(word):
		found[word] = path.duplicate()
	var row := floori(index / float(size))
	var col := index % size
	for dr in [-1, 0, 1]:
		for dc in [-1, 0, 1]:
			if dr == 0 and dc == 0:
				continue
			var r: int = row + dr
			var c: int = col + dc
			if r < 0 or r >= size or c < 0 or c >= size:
				continue
			var next := r * size + c
			if visited[next] == 0:
				_search(board, dictionary, size, next, word, path, visited, found)
	path.pop_back()
	visited[index] = 0
