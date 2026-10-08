class_name WordDictionary
extends RefCounted
## Sorted word list with exact and prefix lookup via binary search.
## A flat PackedStringArray keeps memory low on mobile compared to a hash
## set of every prefix.

var _words := PackedStringArray()


func load_from_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot open dictionary: %s" % path)
		return false
	_words = file.get_as_text().split("\n", false)
	return not _words.is_empty()


func size() -> int:
	return _words.size()


func has_word(word: String) -> bool:
	var i := _lower_bound(word)
	return i < _words.size() and _words[i] == word


func has_prefix(prefix: String) -> bool:
	var i := _lower_bound(prefix)
	return i < _words.size() and _words[i].begins_with(prefix)


## Returns true if the loaded list is sorted by codepoint (required for lookups).
func is_sorted() -> bool:
	for i in range(1, _words.size()):
		if _words[i - 1] >= _words[i]:
			return false
	return true


func _lower_bound(value: String) -> int:
	var lo := 0
	var hi := _words.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if _words[mid] < value:
			lo = mid + 1
		else:
			hi = mid
	return lo
