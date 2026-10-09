extends Node
## Integration test of the multiplayer interface logic: two real MultiplayerUi instances
## (a host and a guest) talk over loopback sockets, driven through the same signals the
## buttons emit. It is a scene so the autoloads exist:
##   godot --headless --path . res://tools/test_mp_ui.tscn --quit-after 4000
## Exits with code 1 if any check fails.

const HISTORY_PATH := "user://test_mp_ui_history.json"

var _checks := 0
var _failures := 0
var _dictionary := WordDictionary.new()
var _host_ui: MultiplayerUi
var _guest_ui: MultiplayerUi
var _host_rounds: Array = []
var _guest_rounds: Array = []
var _host_left := 0
var _guest_left := 0


func _ready() -> void:
	await _run()
	print("checks=%d failures=%d" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("FAIL: %s" % label)


func _wait(condition: Callable, timeout_ms: int = 4000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


func _make_ui(history_name: String) -> MultiplayerUi:
	var ui := MultiplayerUi.new()
	add_child(ui)
	ui.setup(_dictionary, BoardGenerator.new(77))
	ui._history = SessionHistory.new("user://%s" % history_name)
	return ui


func _run() -> void:
	_check(_dictionary.load_from_file("res://data/words_es.txt"), "dictionary loads")
	for name in ["test_mp_ui_host.json", "test_mp_ui_guest.json"]:
		if FileAccess.file_exists("user://" + name):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + name))
	_host_ui = _make_ui("test_mp_ui_host.json")
	_guest_ui = _make_ui("test_mp_ui_guest.json")
	_host_ui.round_begins.connect(func(board: PackedStringArray, countdown: float, duration: float) -> void:
		_host_rounds.append({"board": board, "countdown": countdown, "duration": duration}))
	_guest_ui.round_begins.connect(func(board: PackedStringArray, countdown: float, duration: float) -> void:
		_guest_rounds.append({"board": board, "countdown": countdown, "duration": duration}))
	_host_ui.left_multiplayer.connect(func() -> void: _host_left += 1)
	_guest_ui.left_multiplayer.connect(func() -> void: _guest_left += 1)

	# --- Menu, then the host creates a room -------------------------------------------------
	_host_ui.open()
	_check(_host_ui.screen == MultiplayerUi.Screen.MENU, "the menu opens")
	_host_ui._menu.create_requested.emit("Ana")
	_check(_host_ui.role == MultiplayerUi.Role.HOST and _host_ui.screen == MultiplayerUi.Screen.LOBBY, "creating a room opens the lobby as host")
	_check(_host_ui._lobby.visible and not _host_ui._menu.visible, "only the lobby is visible")
	var port: int = _host_ui._host.port
	_host_ui._host.announce_enabled = false
	_host_ui._host.countdown_seconds = 0.4
	_host_ui._host.round_seconds = 1.5
	_host_ui._host.grace_seconds = 0.4

	# --- A guest joins by typing the address ---------------------------------------------------
	_guest_ui.open()
	_guest_ui._menu.join_requested.emit("Beto")
	_check(_guest_ui.screen == MultiplayerUi.Screen.JOIN, "the guest searches for rooms")
	_guest_ui._join.manual_requested.emit("no es una dirección")
	_check(_guest_ui.role == MultiplayerUi.Role.NONE and _guest_ui._client == null, "a malformed address is refused without connecting")
	_guest_ui._join.manual_requested.emit("127.0.0.1:%d" % port)
	_check(await _wait(func() -> bool: return _guest_ui.role == MultiplayerUi.Role.CLIENT), "the guest joins the room")
	_check(_guest_ui.screen == MultiplayerUi.Screen.LOBBY, "and lands in the lobby")
	_check(await _wait(func() -> bool: return _host_ui._host.session.players().size() == 2), "the host sees two players")
	_check(await _wait(func() -> bool: return _guest_ui._client.roster.size() == 2), "the guest sees two players")
	_check(_host_ui._lobby._data["can_start"], "the host may start with two players")

	# --- A round: both devices start with the same board ----------------------------------------
	_host_ui._lobby.start_requested.emit()
	_check(await _wait(func() -> bool: return _host_rounds.size() == 1 and _guest_rounds.size() == 1), "both devices are told a round begins")
	_check(_host_ui.screen == MultiplayerUi.Screen.GAME and _guest_ui.screen == MultiplayerUi.Screen.GAME, "both are on the game screen")
	_check(_host_rounds[0]["board"] == _guest_rounds[0]["board"], "same board on both devices")
	_check(is_equal_approx(_guest_rounds[0]["countdown"], 0.4) and is_equal_approx(_guest_rounds[0]["duration"], 1.5), "same countdown and duration")

	var board: PackedStringArray = _host_rounds[0]["board"]
	var solutions := BoardSolver.solve(board, _dictionary)
	var words: Array = solutions.keys()
	words.sort_custom(func(a: String, b: String) -> bool: return a.length() < b.length() or (a.length() == b.length() and a < b))
	var shared: String = words[0]
	var only_host: String = words[1]
	var live := {"scores": []}  # a Dictionary: lambdas capture plain locals by value
	_host_ui.scoreboard_updated.connect(func(scores: Array, _id: int) -> void: live["scores"] = scores)
	await get_tree().create_timer(0.55).timeout  # the countdown (0.4 s) is over
	_guest_ui.submit_word(shared)
	_host_ui.submit_word(shared)
	_host_ui.submit_word(only_host)
	_check(await _wait(func() -> bool: return _entry_score(live["scores"], _guest_ui.my_id()) == WordScoring.points_for(shared.length())), "the live board shows the guest's provisional score (shared words not yet removed)")

	# --- The round ends: shared words cancel -------------------------------------------------------
	_check(await _wait(func() -> bool: return _host_ui.screen == MultiplayerUi.Screen.RESULTS and _guest_ui.screen == MultiplayerUi.Screen.RESULTS, 6000), "both devices reach the results")
	var host_ranking: Array = _host_ui._results._ranking
	var guest_ranking: Array = _guest_ui._results._ranking
	_check(host_ranking.size() == 2 and guest_ranking.size() == 2, "two players ranked")
	_check(host_ranking[0]["name"] == "Ana" and host_ranking[0]["score"] == WordScoring.points_for(only_host.length()), "the host wins with the word nobody else found")
	_check(host_ranking[0]["cancelled"] == [shared], "the shared word is struck out")
	_check(host_ranking[1]["name"] == "Beto" and host_ranking[1]["score"] == 0, "the guest scores nothing")
	_check(guest_ranking[0]["id"] == host_ranking[0]["id"], "both devices show the same ranking")
	_check(_host_ui._results._is_host and not _guest_ui._results._is_host, "only the host has the next-round button")
	_check(_host_ui._results._can_continue, "the host can start another round")

	# --- A second round, started from the results screen ----------------------------------------------
	_host_ui._results.next_round_requested.emit()
	_check(await _wait(func() -> bool: return _host_rounds.size() == 2 and _guest_rounds.size() == 2), "the next round starts on both")
	_check(_host_rounds[1]["board"] == _guest_rounds[1]["board"], "again the same board on both")
	_check(await _wait(func() -> bool: return _host_ui.screen == MultiplayerUi.Screen.RESULTS and _guest_ui._results._round == 2, 6000), "round 2 finishes")
	_check(_host_ui._results._table[0]["rounds"] == 2, "the cumulative table counts two rounds")

	# --- Leaving, with a confirmation, and the local history ----------------------------------------------
	_guest_ui.handle_back()
	_check(_guest_ui._dialog.visible, "Back asks for confirmation before leaving a room")
	_guest_ui._dialog.cancelled.emit()
	_guest_ui._dialog.hide_panel()
	_check(_guest_ui.role == MultiplayerUi.Role.CLIENT, "answering 'seguir' keeps the guest in the room")
	_guest_ui._ask_to_leave()
	_guest_ui._dialog.accepted.emit()
	_check(_guest_ui.role == MultiplayerUi.Role.NONE and _guest_left == 1, "leaving returns to the start panel")
	_check(_guest_ui._history.entries().size() == 1 and _guest_ui._history.entries()[0]["rounds"] == 2, "the guest's history keeps the two-round session")
	_check(await _wait(func() -> bool: return not _host_ui._host.session.is_online(_guest_ui.my_id()) or _host_ui._host.session.connected_count() == 1), "the host sees the guest leave")

	_host_ui._ask_to_leave()
	_host_ui._dialog.accepted.emit()
	_check(_host_ui.role == MultiplayerUi.Role.NONE and _host_left == 1, "the host closes the room")
	var host_entries := _host_ui._history.entries()
	_check(host_entries.size() == 1 and host_entries[0]["winner"] == "Ana" and host_entries[0]["players"].size() == 2, "the host's history names the winner")
	_check(await _wait(func() -> bool: return _host_ui._closing_hosts.is_empty()), "the closing room finishes shutting down")

	# --- The host disappears while a guest is inside -----------------------------------------------------------
	var second_host := _make_ui("test_mp_ui_host2.json")
	var second_guest := _make_ui("test_mp_ui_guest2.json")
	var closed_for_guest := []
	second_guest.left_multiplayer.connect(func() -> void: closed_for_guest.append(true))
	second_host._menu.create_requested.emit("Carla")
	var port2: int = second_host._host.port
	second_host._host.announce_enabled = false
	second_guest._menu.join_requested.emit("Diego")
	second_guest._join.manual_requested.emit("127.0.0.1:%d" % port2)
	_check(await _wait(func() -> bool: return second_guest.role == MultiplayerUi.Role.CLIENT), "a guest joins the second room")
	second_host._ask_to_leave()
	second_host._dialog.accepted.emit()
	_check(await _wait(func() -> bool: return second_guest._dialog.visible), "the guest is told the room closed")
	_check(second_guest._dialog.title_label.text == "Sala cerrada", "with the right title")
	second_guest._dialog.accepted.emit()
	_check(closed_for_guest.size() == 1 and second_guest.role == MultiplayerUi.Role.NONE, "accepting returns to the start panel")

	# --- Join failures reach the screen ----------------------------------------------------------------------
	var lonely := _make_ui("test_mp_ui_lonely.json")
	lonely._menu.join_requested.emit("Eva")
	lonely._join.manual_requested.emit("127.0.0.1:47999")  # nobody is listening
	_check(await _wait(func() -> bool: return lonely._join._notice_label.text.contains("No se encontró"), 9000), "an unreachable address shows an explanation")
	_check(MultiplayerUi.join_failure_text("room_full") == "La sala está llena.", "room_full text")
	_check(MultiplayerUi.join_failure_text("round_in_progress").begins_with("La partida ya empezó"), "round_in_progress text")

	for name in ["test_mp_ui_host.json", "test_mp_ui_guest.json", "test_mp_ui_host2.json", "test_mp_ui_guest2.json", "test_mp_ui_lonely.json"]:
		if FileAccess.file_exists("user://" + name):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + name))


func _entry_score(board: Array, player_id: int) -> int:
	for entry: Dictionary in board:
		if entry["id"] == player_id:
			return entry["score"]
	return -1
