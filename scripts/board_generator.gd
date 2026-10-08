class_name BoardGenerator
extends RefCounted
## Generates a 4x4 board of tiles using Spanish letter frequencies.
## A tile is a String: one letter, or "qu" (q is always followed by u in Spanish).
## k and w are included with the lowest possible weight: they are very rare in Spanish.

const SIZE := 4
const MIN_VOWELS := 5
const MAX_VOWELS := 7
const MAX_SAME_VOWEL := 4
const MAX_SAME_CONSONANT := 3
const MAX_RARE_TOTAL := 2
const RARE := ["j", "x", "z", "ñ", "qu", "k", "w"]
const VOWELS := ["a", "e", "i", "o", "u"]
const MAX_ATTEMPTS := 200

## Relative weights (approximate Spanish letter frequencies, per mille).
const WEIGHTS := {
	"e": 137, "a": 125, "o": 87, "s": 80, "r": 69, "n": 67, "i": 63,
	"d": 59, "l": 50, "c": 47, "t": 46, "u": 39, "m": 32, "p": 25,
	"b": 14, "g": 10, "h": 12, "y": 9, "v": 9, "f": 7, "z": 5,
	"j": 4, "ñ": 3, "x": 2, "qu": 9, "k": 1, "w": 1,
}

var _rng := RandomNumberGenerator.new()
var _tiles: Array[String] = []
var _cumulative: Array[int] = []
var _total := 0


func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	for tile: String in WEIGHTS:
		_total += WEIGHTS[tile]
		_tiles.append(tile)
		_cumulative.append(_total)


func generate() -> PackedStringArray:
	var board := _draw_board()
	for _attempt in MAX_ATTEMPTS:
		if _is_valid(board):
			return board
		board = _draw_board()
	push_warning("BoardGenerator: no valid board in %d attempts, using last draw" % MAX_ATTEMPTS)
	return board


## Like generate(), but rejects boards with fewer than min_words findable words.
func generate_playable(dictionary: WordDictionary, min_words: int = 100) -> PackedStringArray:
	var board := generate()
	for _attempt in MAX_ATTEMPTS:
		if BoardSolver.solve(board, dictionary).size() >= min_words:
			return board
		board = generate()
	push_warning("BoardGenerator: no playable board in %d attempts" % MAX_ATTEMPTS)
	return board


func _draw_board() -> PackedStringArray:
	var board := PackedStringArray()
	for _i in SIZE * SIZE:
		board.append(_draw_tile())
	return board


func _draw_tile() -> String:
	var roll := _rng.randi_range(1, _total)
	for i in _tiles.size():
		if roll <= _cumulative[i]:
			return _tiles[i]
	return _tiles[-1]


func _is_valid(board: PackedStringArray) -> bool:
	var counts := {}
	var vowels := 0
	var rare := 0
	for tile in board:
		counts[tile] = counts.get(tile, 0) + 1
		if tile in VOWELS:
			vowels += 1
		if tile in RARE:
			rare += 1
	if vowels < MIN_VOWELS or vowels > MAX_VOWELS or rare > MAX_RARE_TOTAL:
		return false
	for tile: String in counts:
		var limit := MAX_SAME_VOWEL if tile in VOWELS else MAX_SAME_CONSONANT
		if tile in RARE:
			limit = 1
		if counts[tile] > limit:
			return false
	return true
