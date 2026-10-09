extends SceneTree
## Headless tests for the multiplayer room logic (no networking involved).
## Run: godot --headless --path . --quit-after 900 -s tools/test_room.gd
## Exits with code 1 if any check fails.

const HISTORY_PATH := "user://test_room_history.json"

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_word_points()
	_test_sanitize_name()
	_test_join_rules()
	_test_start_rules()
	_test_submit_word()
	_test_cancellation()
	_test_single_player_and_triples()
	_test_ranking_ties()
	_test_two_rounds_and_table()
	_test_disconnects()
	_test_provisional_board()
	_test_history()
	print("checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("FAIL: %s" % label)


func _two_players() -> RoomSession:
	var session := RoomSession.new()
	session.add_player(1, "Ana")
	session.add_player(2, "Beto")
	return session


func _valid(words: Array) -> Dictionary:
	var result := {}
	for word in words:
		result[word] = [0]
	return result


func _board() -> PackedStringArray:
	return PackedStringArray(["e", "s", "c", "o", "d", "i", "d", "n", "a", "s", "t", "e", "l", "o", "r", "a"])


func _test_word_points() -> void:
	_check(WordScoring.points_for(3) == 1, "3 letters = 1")
	_check(WordScoring.points_for(4) == 2, "4 letters = 2")
	_check(WordScoring.points_for(5) == 2, "5 letters = 2")
	_check(WordScoring.points_for(6) == 3, "6 letters = 3")
	_check(WordScoring.points_for(7) == 4, "7 letters = 4")
	_check(WordScoring.points_for(8) == 4, "8 letters = 4")
	_check(WordScoring.points_for(16) == 4, "16 letters = 4")
	_check(RoundLength.seconds(0) == 60.0 and RoundLength.seconds(1) == 140.0 and RoundLength.seconds(2) == 185.0, "round lengths: 1:00, 2:20, 3:05")
	_check(RoundLength.clock(1) == "2:20" and RoundLength.clock(2) == "3:05", "clock text")
	_check(RoundLength.label(0) == "Rápida · 1:00", "label text")
	_check(RoundLength.spoken(0) == "1 minuto" and RoundLength.spoken(1) == "2 minutos y 20 segundos" and RoundLength.spoken(2) == "3 minutos y 5 segundos", "spoken text")
	_check(RoundLength.seconds(99) == 185.0 and RoundLength.seconds(-1) == 60.0, "an index out of range is clamped")


func _test_sanitize_name() -> void:
	_check(RoomSession.sanitize_name("  Ana  ") == "Ana", "trims spaces")
	_check(RoomSession.sanitize_name("A\nB\tC") == "A B C", "control chars become spaces")
	_check(RoomSession.sanitize_name("Juan    Pérez") == "Juan Pérez", "collapses spaces")
	_check(RoomSession.sanitize_name("") == "Jugador", "empty -> default")
	_check(RoomSession.sanitize_name("   \n ") == "Jugador", "blank -> default")
	_check(RoomSession.sanitize_name("Ñandú") == "Ñandú", "keeps ñ and accents")
	var long_name := RoomSession.sanitize_name("x".repeat(40))
	_check(long_name.length() == RoomSession.MAX_NAME_LENGTH, "long name is cut to the maximum")
	_check(RoomSession.sanitize_name("abcdefghijklmno pqrstu") == "abcdefghijklmno", "cut name is re-trimmed")


func _test_join_rules() -> void:
	var session := RoomSession.new()
	var first := session.add_player(1, "Ana")
	_check(first["ok"] and first["name"] == "Ana", "first player joins with their name")
	var second := session.add_player(2, "ana")
	_check(second["ok"] and second["name"] == "ana 2", "same name ignoring case gets a number")
	var third := session.add_player(3, "Ana")
	_check(third["name"] == "Ana 3", "third Ana gets 3")
	var again := session.add_player(1, "Otro")
	_check(not again["ok"] and again["reason"] == "duplicate_id", "same id cannot join twice")

	var max_session := RoomSession.new()
	var base := "ABCDEFGHIJKLMNOP"  # exactly MAX_NAME_LENGTH
	max_session.add_player(1, base)
	var renamed := max_session.add_player(2, base)
	_check(renamed["name"].length() <= RoomSession.MAX_NAME_LENGTH, "numbered name still fits")
	_check(renamed["name"] != base and renamed["name"].ends_with(" 2"), "numbered name is distinct")

	var full := RoomSession.new()
	for i in RoomSession.MAX_PLAYERS:
		_check(full.add_player(100 + i, "P%d" % i)["ok"], "player %d fits" % i)
	var ninth := full.add_player(999, "Extra")
	_check(not ninth["ok"] and ninth["reason"] == "room_full", "room is full at 8")

	var running := _two_players()
	running.start_round(_board(), _valid(["casa"]))
	var late := running.add_player(3, "Tarde")
	_check(not late["ok"] and late["reason"] == "round_in_progress", "nobody joins during a round")

	var leaving := RoomSession.new()
	leaving.add_player(1, "Ana")
	leaving.remove_player(1)
	_check(leaving.players().is_empty(), "leaving the lobby removes the player")
	_check(leaving.add_player(2, "Ana")["name"] == "Ana", "the name is free again")
	_check(not leaving.remove_player(77), "removing an unknown id reports false")


func _test_start_rules() -> void:
	var alone := RoomSession.new()
	alone.add_player(1, "Ana")
	_check(not alone.can_start(), "one player cannot start")
	_check(not alone.start_round(_board(), _valid(["casa"])), "start_round refuses with one player")
	var pair := _two_players()
	_check(pair.can_start(), "two players can start")
	_check(pair.start_round(_board(), _valid(["casa"])), "start_round works with two")
	_check(pair.phase == RoomSession.Phase.PLAYING and pair.round_number == 1, "phase and round number")
	_check(not pair.can_start(), "cannot start while a round runs")


func _test_submit_word() -> void:
	var lobby := _two_players()
	_check(lobby.submit_word(1, "casa")["status"] == "not_playing", "no words before the round")

	var session := _two_players()
	session.start_round(_board(), _valid(["casa", "luna", "perro", "sol"]))
	var ok := session.submit_word(1, "casa")
	_check(ok["status"] == "ok" and ok["points"] == 2 and ok["total"] == 2, "valid word scores")
	_check(session.submit_word(1, "casa")["status"] == "duplicate", "repeat by the same player")
	_check(session.submit_word(1, " CASA ")["status"] == "duplicate", "repeat after normalizing case and spaces")
	_check(session.submit_word(1, "xyzw")["status"] == "invalid", "word not on the board")
	_check(session.submit_word(1, "al")["status"] == "too_short", "shorter than 3 letters")
	_check(session.submit_word(99, "casa")["status"] == "unknown_player", "unknown player")
	var five := session.submit_word(2, "perro")
	_check(five["status"] == "ok" and five["points"] == 2, "5 letters = 2 points")
	_check(session.provisional_points(1) == 2 and session.provisional_points(2) == 2, "provisional totals")
	_check(session.submit_word(2, "casa")["status"] == "ok", "the same word by another player is accepted live")


func _test_cancellation() -> void:
	var scored := RoomScoring.score_round({
		1: ["casa", "perro", "gato"],
		2: ["casa", "luna"],
		3: ["luna", "sol", "gato"],
	})
	_check(scored[1]["score"] == 2 and scored[1]["counted"] == ["perro"], "A keeps only perro")
	_check(scored[1]["cancelled"] == ["casa", "gato"], "A loses casa and gato")
	_check(scored[2]["score"] == 0 and scored[2]["counted"].is_empty(), "B scores nothing")
	_check(scored[2]["cancelled"] == ["casa", "luna"], "B loses casa and luna")
	_check(scored[3]["score"] == 1 and scored[3]["counted"] == ["sol"], "C keeps only sol")
	var ranking := RoomScoring.rank(scored, {1: "A", 2: "B", 3: "C"})
	_check(ranking[0]["id"] == 1 and ranking[1]["id"] == 3 and ranking[2]["id"] == 2, "ranking A, C, B")
	_check(ranking[0]["rank"] == 1 and ranking[1]["rank"] == 2 and ranking[2]["rank"] == 3, "ranks 1, 2, 3")
	var repeated := RoomScoring.score_round({1: ["casa", "casa", "casa"], 2: ["luna"]})
	_check(repeated[1]["counted"] == ["casa"] and repeated[1]["score"] == 2, "a repeated word inside one list counts once")


func _test_single_player_and_triples() -> void:
	var alone := RoomScoring.score_round({1: ["casa", "perro"]})
	_check(alone[1]["score"] == 4 and alone[1]["cancelled"].is_empty(), "alone, nothing is cancelled")
	var triple := RoomScoring.score_round({1: ["casa"], 2: ["casa"], 3: ["casa"]})
	_check(triple[1]["score"] == 0 and triple[2]["score"] == 0 and triple[3]["score"] == 0, "three players, same word: nobody")
	var nobody := RoomScoring.score_round({})
	_check(nobody.is_empty(), "empty round")


func _test_ranking_ties() -> void:
	var tied := RoomScoring.score_round({
		1: ["perro"],
		2: ["mundo"],
		3: ["sol"],
	})
	var ranking := RoomScoring.rank(tied, {1: "Ana", 2: "Beto", 3: "Carla"})
	_check(ranking[0]["rank"] == 1 and ranking[1]["rank"] == 1, "tied on score and words share rank 1")
	_check(ranking[2]["rank"] == 3, "the next rank skips to 3")
	_check(ranking[0]["name"] == "Ana" and ranking[1]["name"] == "Beto", "tied players ordered by name")

	var by_words := RoomScoring.score_round({
		1: ["sol", "mar", "pan", "paz"],
		2: ["mundo", "perro"],
	})
	var ordered := RoomScoring.rank(by_words, {1: "Ana", 2: "Beto"})
	_check(by_words[1]["score"] == 4 and by_words[2]["score"] == 4, "both have 4 points")
	_check(ordered[0]["id"] == 1 and ordered[0]["rank"] == 1 and ordered[1]["rank"] == 2, "more counted words wins the tie")


func _test_two_rounds_and_table() -> void:
	var session := _two_players()
	session.start_round(_board(), _valid(["casa", "luna", "perro", "sol"]))
	session.submit_word(1, "casa")
	session.submit_word(1, "perro")
	session.submit_word(1, "sol")
	session.submit_word(2, "casa")
	session.submit_word(2, "luna")
	var first := session.finish_round()
	_check(first[0]["id"] == 1 and first[0]["score"] == 3 and first[0]["rank"] == 1, "round 1: Ana wins with perro and sol")
	_check(first[1]["score"] == 2 and first[1]["cancelled"] == ["casa"], "round 1: Beto keeps luna, loses casa")
	_check(session.phase == RoomSession.Phase.RESULTS, "phase after finishing")
	_check(session.finish_round().is_empty(), "finishing twice does nothing")

	_check(session.start_round(_board(), _valid(["sol"])), "a new round can start from the results")
	session.submit_word(1, "sol")
	session.submit_word(2, "sol")
	var second := session.finish_round()
	_check(second[0]["score"] == 0 and second[1]["score"] == 0, "round 2: the shared word cancels for both")

	session.start_round(_board(), _valid(["perro"]))
	session.submit_word(2, "perro")
	session.finish_round()

	var table := session.cumulative_table()
	_check(session.round_number == 3, "three rounds played")
	_check(table[0]["name"] == "Beto" and table[0]["points"] == 4 and table[0]["wins"] == 1, "Beto: 2 + 0 + 2 points, 1 win")
	_check(table[1]["name"] == "Ana" and table[1]["points"] == 3 and table[1]["wins"] == 1, "Ana: 3 points, 1 win")
	_check(table[0]["rounds"] == 3, "rounds played counted")
	var entry := session.history_entry(1700000000)
	_check(entry["winner"] == "Beto" and entry["rounds"] == 3 and entry["time"] == 1700000000, "history entry summary")
	_check(entry["players"][0]["name"] == "Beto", "history keeps the cumulative order")
	_check(RoomSession.new().history_entry(1).is_empty(), "no history entry without rounds")


func _test_disconnects() -> void:
	var session := RoomSession.new()
	session.add_player(1, "Ana")
	session.add_player(2, "Beto")
	session.add_player(3, "Carla")
	session.start_round(_board(), _valid(["casa", "luna", "sol", "perro"]))
	session.submit_word(3, "sol")
	session.submit_word(3, "casa")
	session.submit_word(1, "casa")
	session.submit_word(1, "perro")
	_check(session.remove_player(3), "Carla disconnects mid-round")
	_check(session.has_player(3) and not session.players()[2]["connected"], "she stays listed as disconnected")
	_check(session.submit_word(3, "luna")["status"] == "not_in_round", "a disconnected player cannot submit")
	var ranking := session.finish_round()
	var by_id := {}
	for entry: Dictionary in ranking:
		by_id[entry["id"]] = entry
	_check(by_id[3]["counted"] == ["sol"] and by_id[3]["score"] == 1, "her earlier words still count")
	_check(by_id[1]["cancelled"] == ["casa"], "her words still cancel duplicates")
	_check(by_id[3]["connected"] == false, "ranking flags her as disconnected")
	_check(session.cumulative_table().size() == 3, "she stays in the cumulative table")
	_check(session.connected_count() == 2, "two players remain connected")
	session.start_round(_board(), _valid(["casa"]))
	_check(session.provisional_board().size() == 2, "the next round only has connected players")
	var replacement := RoomSession.new()
	_check(replacement.add_player(1, "Ana")["ok"], "sanity: a fresh room accepts players")


func _test_provisional_board() -> void:
	var session := _two_players()
	session.start_round(_board(), _valid(["casa", "perro"]))
	session.submit_word(1, "casa")
	session.submit_word(2, "casa")
	session.submit_word(2, "perro")
	var live := session.provisional_board()
	_check(live.size() == 2, "live board lists both players")
	_check(live[0]["score"] == 2 and live[1]["score"] == 4, "live scores are provisional: shared words still count")
	_check(not live[0].has("words") and not live[1].has("words"), "the live board never carries the words")


func _test_history() -> void:
	_delete_file(HISTORY_PATH)
	var history := SessionHistory.new(HISTORY_PATH)
	_check(history.entries().is_empty(), "history starts empty")
	for i in range(1, 26):
		history.add({"time": i, "rounds": 2, "players": [{"name": "Ana", "points": i, "wins": 1}], "winner": "Ana"})
	var kept := history.entries()
	_check(kept.size() == SessionHistory.MAX_ENTRIES, "history is capped at 20")
	_check(kept[0]["time"] == 25 and kept[19]["time"] == 6, "newest first, oldest dropped")

	var reloaded := SessionHistory.new(HISTORY_PATH)
	var from_disk := reloaded.entries()
	_check(from_disk.size() == 20 and from_disk[0]["time"] == 25, "history survives a reload")
	_check(typeof(from_disk[0]["time"]) == TYPE_INT, "numbers come back as integers")
	_check(typeof(from_disk[0]["players"][0]["points"]) == TYPE_INT, "nested numbers come back as integers")

	reloaded.add({"nonsense": true})
	reloaded.add({"players": []})
	_check(reloaded.entries().size() == 20, "malformed entries are ignored")

	var file := FileAccess.open(HISTORY_PATH, FileAccess.WRITE)
	file.store_string("this is not json {{{")
	file.close()
	_check(SessionHistory.new(HISTORY_PATH).entries().is_empty(), "a corrupted file starts empty")

	var cleared := SessionHistory.new(HISTORY_PATH)
	cleared.add({"time": 1, "rounds": 1, "players": [{"name": "Ana", "points": 1, "wins": 0}], "winner": ""})
	cleared.clear()
	_check(SessionHistory.new(HISTORY_PATH).entries().is_empty(), "clear empties the file too")
	_delete_file(HISTORY_PATH)


func _delete_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
