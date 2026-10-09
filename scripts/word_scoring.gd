class_name WordScoring
extends RefCounted
## Classic Boggle points by word length, shared by the single-player round and the
## multiplayer scoring. A "qu" tile counts as two letters because a word is the
## concatenation of its tiles.


static func points_for(length: int) -> int:
	if length <= 4:
		return 1
	match length:
		5:
			return 2
		6:
			return 3
		7:
			return 5
	return 11
