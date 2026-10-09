class_name WordScoring
extends RefCounted
## Points by word length, shared by the single-player round and the multiplayer scoring.
## A "qu" tile counts as two letters because a word is the concatenation of its tiles.
## 3 letters: 1, 4-5 letters: 2, 6 letters: 3, 7 or more: 4.


static func points_for(length: int) -> int:
	if length <= 3:
		return 1
	if length <= 5:
		return 2
	if length == 6:
		return 3
	return 4
