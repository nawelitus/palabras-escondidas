class_name RoomScoring
extends RefCounted
## Final scoring of one multiplayer round. A word found by two or more players
## counts for nobody: only words found by exactly one player score.


## words_by_player: {player_id: Array of words}.
## Returns {player_id: {"score": int, "counted": Array[String], "cancelled": Array[String]}}.
## Repeated words inside one player's list are counted once.
static func score_round(words_by_player: Dictionary) -> Dictionary:
	var finders := {}  # word -> how many players found it
	var unique_words := {}  # player_id -> Array[String], without repeats, in order
	for player_id in words_by_player:
		var seen := {}
		var list: Array[String] = []
		for raw in words_by_player[player_id]:
			var word := String(raw)
			if seen.has(word):
				continue
			seen[word] = true
			list.append(word)
			finders[word] = int(finders.get(word, 0)) + 1
		unique_words[player_id] = list

	var result := {}
	for player_id in unique_words:
		var counted: Array[String] = []
		var cancelled: Array[String] = []
		var score := 0
		for word: String in unique_words[player_id]:
			if finders[word] == 1:
				counted.append(word)
				score += WordScoring.points_for(word.length())
			else:
				cancelled.append(word)
		result[player_id] = {"score": score, "counted": counted, "cancelled": cancelled}
	return result


## Orders the result of score_round from highest to lowest score.
## names: {player_id: display name}. Each entry gets a "rank" (1 = best); players
## tied on score and on number of counted words share the same rank (1, 1, 3, ...).
## Ties are ordered by more counted words first, then by name.
static func rank(scored: Dictionary, names: Dictionary) -> Array:
	var entries: Array = []
	for player_id in scored:
		var item: Dictionary = scored[player_id]
		entries.append({
			"id": player_id,
			"name": String(names.get(player_id, "")),
			"score": item["score"],
			"counted": item["counted"],
			"cancelled": item["cancelled"],
			"rank": 0,
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _is_before(a, b))

	var previous := {}
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var tied: bool = i > 0 \
			and entry["score"] == previous["score"] \
			and entry["counted"].size() == previous["counted"].size()
		entry["rank"] = previous["rank"] if tied else i + 1
		previous = entry
	return entries


static func _is_before(a: Dictionary, b: Dictionary) -> bool:
	if a["score"] != b["score"]:
		return a["score"] > b["score"]
	var counted_a: int = a["counted"].size()
	var counted_b: int = b["counted"].size()
	if counted_a != counted_b:
		return counted_a > counted_b
	var name_a := String(a["name"]).to_lower()
	var name_b := String(b["name"]).to_lower()
	if name_a != name_b:
		return name_a < name_b
	return int(a["id"]) < int(b["id"])
