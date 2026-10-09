class_name RoomSession
extends RefCounted
## State of one multiplayer room, with no networking in it: who is in the room,
## the round in progress, the words each player submitted, the final ranking and
## the cumulative table. The host owns the only authoritative instance; the
## network layer only moves messages in and out of it.

enum Phase { LOBBY, PLAYING, RESULTS }

const MAX_PLAYERS := 8
const MIN_PLAYERS_TO_START := 2
const MAX_NAME_LENGTH := 16
const MIN_WORD_LENGTH := 3
const DEFAULT_NAME := "Jugador"

var phase := Phase.LOBBY
var round_number := 0
var board := PackedStringArray()

var _players := {}  # id -> {"name": String, "connected": bool}
var _join_order: Array[int] = []
var _valid_words := {}  # word -> path, from BoardSolver.solve, used to validate submissions
var _submissions := {}  # id -> Array[String], in submission order, for the current round
var _totals := {}  # id -> {"points": int, "wins": int, "rounds": int}


## Cleans a typed name: control characters become spaces, runs of spaces collapse,
## the result is trimmed and cut to MAX_NAME_LENGTH. An empty name becomes "Jugador".
static func sanitize_name(raw: String) -> String:
	var cleaned := ""
	for i in raw.length():
		var code := raw.unicode_at(i)
		cleaned += " " if code < 32 or code == 127 else raw[i]
	var result := " ".join(cleaned.split(" ", false))
	if result.length() > MAX_NAME_LENGTH:
		result = result.substr(0, MAX_NAME_LENGTH).strip_edges()
	return result if not result.is_empty() else DEFAULT_NAME


## Result: {"ok": bool, "reason": String, "name": String}. The name is the final one
## (cleaned, and numbered like "Ana 2" if someone already uses it, ignoring case).
## Reasons: duplicate_id, round_in_progress, room_full.
func add_player(player_id: int, requested_name: String) -> Dictionary:
	if _players.has(player_id):
		return {"ok": false, "reason": "duplicate_id", "name": ""}
	if phase == Phase.PLAYING:
		return {"ok": false, "reason": "round_in_progress", "name": ""}
	if connected_count() >= MAX_PLAYERS:
		return {"ok": false, "reason": "room_full", "name": ""}
	var final_name := _unique_name(sanitize_name(requested_name))
	_players[player_id] = {"name": final_name, "connected": true}
	_join_order.append(player_id)
	_totals[player_id] = {"points": 0, "wins": 0, "rounds": 0}
	return {"ok": true, "reason": "", "name": final_name}


## Before the first round the player simply leaves. Once rounds have been played, or
## while one is running, the player stays in the books as disconnected: the words
## already submitted keep counting and the cumulative points are not lost.
func remove_player(player_id: int) -> bool:
	if not _players.has(player_id):
		return false
	if phase == Phase.LOBBY and round_number == 0:
		_players.erase(player_id)
		_join_order.erase(player_id)
		_totals.erase(player_id)
		_submissions.erase(player_id)
	else:
		_players[player_id]["connected"] = false
	return true


func has_player(player_id: int) -> bool:
	return _players.has(player_id)


func player_name(player_id: int) -> String:
	return String(_players[player_id]["name"]) if _players.has(player_id) else ""


func connected_count() -> int:
	var count := 0
	for player_id in _players:
		if _players[player_id]["connected"]:
			count += 1
	return count


## Everyone in the room in joining order: [{"id", "name", "connected"}].
func players() -> Array:
	var list: Array = []
	for player_id in _join_order:
		list.append({
			"id": player_id,
			"name": _players[player_id]["name"],
			"connected": _players[player_id]["connected"],
		})
	return list


func can_start() -> bool:
	return phase != Phase.PLAYING and connected_count() >= MIN_PLAYERS_TO_START


## valid_words: the result of BoardSolver.solve for this board; the host validates
## every submission against it. Only connected players take part in the round.
func start_round(round_board: PackedStringArray, valid_words: Dictionary) -> bool:
	if not can_start():
		return false
	board = round_board
	_valid_words = valid_words
	round_number += 1
	_submissions.clear()
	for player_id in _join_order:
		if _players[player_id]["connected"]:
			_submissions[player_id] = []
	phase = Phase.PLAYING
	return true


## Result: {"status": String, "points": int, "total": int}. status is "ok" or one of
## not_playing, unknown_player, not_in_round, too_short, duplicate, invalid.
## On "ok", points is what the word is worth and total the player's provisional score.
func submit_word(player_id: int, raw_word: String) -> Dictionary:
	if phase != Phase.PLAYING:
		return {"status": "not_playing", "points": 0, "total": 0}
	if not _players.has(player_id):
		return {"status": "unknown_player", "points": 0, "total": 0}
	if not _players[player_id]["connected"] or not _submissions.has(player_id):
		return {"status": "not_in_round", "points": 0, "total": provisional_points(player_id)}
	var word := raw_word.strip_edges().to_lower()
	var total := provisional_points(player_id)
	if word.length() < MIN_WORD_LENGTH:
		return {"status": "too_short", "points": 0, "total": total}
	if word in _submissions[player_id]:
		return {"status": "duplicate", "points": 0, "total": total}
	if not _valid_words.has(word):
		return {"status": "invalid", "points": 0, "total": total}
	_submissions[player_id].append(word)
	var points := WordScoring.points_for(word.length())
	return {"status": "ok", "points": points, "total": total + points}


## What a player has so far, repeated words not yet removed.
func provisional_points(player_id: int) -> int:
	var total := 0
	for word: String in _submissions.get(player_id, []):
		total += WordScoring.points_for(word.length())
	return total


## Live scoreboard: [{"id", "name", "connected", "score"}] in joining order, only for
## the players of the current round. These are PROVISIONAL scores: a word found by
## two players only cancels when the round ends. Never include the words themselves.
func provisional_board() -> Array:
	var list: Array = []
	for player_id in _join_order:
		if _submissions.has(player_id):
			list.append({
				"id": player_id,
				"name": _players[player_id]["name"],
				"connected": _players[player_id]["connected"],
				"score": provisional_points(player_id),
			})
	return list


## Ends the round: removes the words found by several players, orders the players
## and updates the cumulative table. Returns [{"id", "name", "connected", "score",
## "counted", "cancelled", "rank"}] from best to worst; empty if no round is running.
## Every player with rank 1 and a score above zero is credited a win.
func finish_round() -> Array:
	if phase != Phase.PLAYING:
		return []
	var scored := RoomScoring.score_round(_submissions)
	var names := {}
	for player_id in scored:
		names[player_id] = _players[player_id]["name"]
	var ranking := RoomScoring.rank(scored, names)
	for entry: Dictionary in ranking:
		var player_id: int = entry["id"]
		entry["connected"] = _players[player_id]["connected"]
		var totals: Dictionary = _totals[player_id]
		totals["points"] += entry["score"]
		totals["rounds"] += 1
		if entry["rank"] == 1 and entry["score"] > 0:
			totals["wins"] += 1
	phase = Phase.RESULTS
	return ranking


## Cumulative table of the room: [{"id", "name", "connected", "points", "wins",
## "rounds"}] by points, then wins, then name.
func cumulative_table() -> Array:
	var table: Array = []
	for player_id in _join_order:
		var totals: Dictionary = _totals[player_id]
		table.append({
			"id": player_id,
			"name": _players[player_id]["name"],
			"connected": _players[player_id]["connected"],
			"points": totals["points"],
			"wins": totals["wins"],
			"rounds": totals["rounds"],
		})
	table.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["points"] != b["points"]:
			return a["points"] > b["points"]
		if a["wins"] != b["wins"]:
			return a["wins"] > b["wins"]
		return String(a["name"]).to_lower() < String(b["name"]).to_lower())
	return table


## Summary stored in the local history when the room closes. Empty if no round was played.
func history_entry(unix_time: int) -> Dictionary:
	if round_number == 0:
		return {}
	var table := cumulative_table()
	var summary: Array = []
	for row: Dictionary in table:
		summary.append({"name": row["name"], "points": row["points"], "wins": row["wins"]})
	var winner := String(table[0]["name"]) if table[0]["points"] > 0 else ""
	return {"time": unix_time, "rounds": round_number, "players": summary, "winner": winner}


func _unique_name(base: String) -> String:
	if not _name_taken(base):
		return base
	for n in range(2, 1000):
		var suffix := " %d" % n
		var candidate := base.substr(0, MAX_NAME_LENGTH - suffix.length()).strip_edges() + suffix
		if not _name_taken(candidate):
			return candidate
	return base


func _name_taken(candidate: String) -> bool:
	var wanted := candidate.to_lower()
	for player_id in _players:
		if String(_players[player_id]["name"]).to_lower() == wanted:
			return true
	return false
