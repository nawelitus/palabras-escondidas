class_name MultiplayerUi
extends Control
## Everything multiplayer on the interface side: it owns the host or the client, the
## room discovery and the local history, moves between the multiplayer screens, and
## talks to the game screen (main.gd) through a few signals. While no multiplayer
## screen is open it lets every touch through to the game underneath.

## Emitted when a round is about to start on this device (countdown first, then play).
signal round_begins(board: PackedStringArray, countdown: float, duration: float)
## Provisional scores of everybody, for the live scoreboard.
signal scoreboard_updated(board: Array, my_id: int)
## The player left multiplayer (or the room closed): go back to the start panel.
signal left_multiplayer
## The results of a round arrived (whether the clock ran out or the host ended it early).
signal round_ended

enum Role { NONE, HOST, CLIENT }
enum Screen { NONE, MENU, JOIN, LOBBY, GAME, RESULTS, HISTORY }
enum DialogAction { NONE, CONFIRM_LEAVE, ROOM_CLOSED }

const MIN_PLAYABLE_WORDS := 100
const ROOM_REFRESH_MS := 500

var role := Role.NONE
var screen := Screen.NONE

var _dictionary: WordDictionary
var _generator: BoardGenerator
var _host: RoomHost
var _client: RoomClient
var _discovery := LanDiscovery.new()
var _history := SessionHistory.new()
var _my_id := 0
var _player_name := ""
var _dialog_action := DialogAction.NONE
var _next_room_refresh_ms := 0
## Rooms that were closed by the player and are still finishing (the goodbye needs a moment).
var _closing_hosts: Array[RoomHost] = []

var _menu := MpMenuView.new()
var _join := MpJoinView.new()
var _lobby := MpLobbyView.new()
var _results := MpResultsView.new()
var _history_view := MpHistoryView.new()
var _dialog := MpDialogView.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for view: MpPanel in [_menu, _join, _lobby, _results, _history_view, _dialog]:
		add_child(view)

	_menu.create_requested.connect(_on_create_requested)
	_menu.join_requested.connect(_on_join_requested)
	_menu.history_requested.connect(_on_history_requested)
	_menu.back_requested.connect(_leave_multiplayer_menu)
	_join.room_chosen.connect(_connect_to)
	_join.manual_requested.connect(_on_manual_address)
	_join.back_requested.connect(_on_join_back)
	_lobby.start_requested.connect(_on_start_requested)
	_lobby.duration_requested.connect(_on_duration_requested)
	_lobby.leave_requested.connect(_ask_to_leave)
	_results.next_round_requested.connect(_on_start_requested)
	_results.duration_requested.connect(_on_duration_requested)
	_results.leave_requested.connect(_ask_to_leave)
	_show_duration()
	_history_view.back_requested.connect(_on_history_back)
	_dialog.accepted.connect(_on_dialog_accepted)
	_dialog.cancelled.connect(_on_dialog_cancelled)


func setup(dictionary: WordDictionary, generator: BoardGenerator) -> void:
	_dictionary = dictionary
	_generator = generator


func apply_skin(skin: GameSkin) -> void:
	for view: MpPanel in [_menu, _join, _lobby, _results, _history_view, _dialog]:
		view.apply_skin(skin)


## Opens the multiplayer menu from the start panel.
func open() -> void:
	_show(Screen.MENU)


func is_in_room() -> bool:
	return role != Role.NONE


func my_id() -> int:
	return _my_id


## True while this device hosts a room and a round is being played (it can end it early).
func can_finish_round() -> bool:
	return role == Role.HOST and _host != null and _host.session.phase == RoomSession.Phase.PLAYING


## The host ends the round for everybody, without waiting for the clock.
func finish_round_early() -> void:
	if can_finish_round():
		_host.finish_now()


## Sends a word found by this player. The host and the guests are checked the same way.
func submit_word(word: String) -> void:
	if role == Role.HOST and _host != null:
		_host.submit_local_word(word)
	elif role == Role.CLIENT and _client != null:
		_client.submit_word(word)


## Android back button. Returns true if a multiplayer screen took it.
func handle_back() -> bool:
	if _dialog.visible:
		_dialog.hide_panel()
		_on_dialog_cancelled()
		return true
	match screen:
		Screen.NONE:
			return false
		Screen.MENU:
			_leave_multiplayer_menu()
		Screen.JOIN:
			_on_join_back()
		Screen.HISTORY:
			_on_history_back()
		_:
			_ask_to_leave()
	return true


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _host != null:
		_host.poll()
	if _client != null:
		_client.poll()
	for closing in _closing_hosts:
		closing.poll()
	_closing_hosts = _closing_hosts.filter(func(room: RoomHost) -> bool: return not room.is_closed())
	if screen == Screen.JOIN:
		_discovery.poll(now)
		if now >= _next_room_refresh_ms:
			_next_room_refresh_ms = now + ROOM_REFRESH_MS
			_join.set_rooms(_discovery.rooms(now))


# --- Screen switching ----------------------------------------------------------------

func _show(target: Screen) -> void:
	screen = target
	for view: MpPanel in [_menu, _join, _lobby, _results, _history_view]:
		view.hide_panel()
	match target:
		Screen.MENU:
			_menu.show_panel()
		Screen.JOIN:
			_join.set_notice("")
			_join.show_panel()
		Screen.LOBBY:
			_lobby.show_panel()
			_refresh_lobby()
		Screen.RESULTS:
			_results.show_panel()
		Screen.HISTORY:
			_history_view.set_entries(_history.entries())
			_history_view.show_panel()


func _leave_multiplayer_menu() -> void:
	_show(Screen.NONE)
	left_multiplayer.emit()


func _on_history_requested() -> void:
	_show(Screen.HISTORY)


func _on_history_back() -> void:
	_show(Screen.MENU)


# --- Creating a room --------------------------------------------------------------------

func _on_create_requested(player_name: String) -> void:
	_player_name = player_name
	var host := RoomHost.new()
	host.board_factory = _make_board
	host.round_seconds = RoundLength.seconds(GameSettings.duration_index)
	_show_duration()
	if host.open(player_name) != OK:
		_dialog_action = DialogAction.NONE
		_dialog.ask("No se pudo crear la sala", "Revisa que estés conectado a una red wifi e inténtalo de nuevo.")
		return
	_host = host
	role = Role.HOST
	_my_id = host.host_id
	host.roster_changed.connect(_on_host_roster_changed)
	host.scoreboard_changed.connect(func(board: Array) -> void: scoreboard_updated.emit(board, _my_id))
	host.round_started.connect(_on_round_started)
	host.round_finished.connect(_on_round_finished)
	_show(Screen.LOBBY)


func _make_board() -> Dictionary:
	var board := _generator.generate_playable(_dictionary, MIN_PLAYABLE_WORDS)
	return {"board": board, "words": BoardSolver.solve(board, _dictionary)}


func _on_start_requested() -> void:
	if _host == null or not _host.start_round():
		_dialog_action = DialogAction.NONE
		_dialog.ask("No se puede empezar", "Se necesitan al menos %d jugadores conectados." % RoomSession.MIN_PLAYERS_TO_START)


## The host picks the round length for the next round; guests follow the one in `start`.
func _on_duration_requested() -> void:
	if role != Role.HOST or _host == null:
		return
	GameSettings.cycle_duration()
	_host.round_seconds = RoundLength.seconds(GameSettings.duration_index)
	_show_duration()


func _show_duration() -> void:
	var text := RoundLength.label(GameSettings.duration_index)
	_lobby.set_duration_text(text)
	_results.set_duration_text(text)


func _on_host_roster_changed() -> void:
	if screen == Screen.LOBBY:
		_refresh_lobby()
	elif screen == Screen.RESULTS and _host != null:
		_results.set_can_continue(_host.session.can_start())


# --- Joining a room ---------------------------------------------------------------------

func _on_join_requested(player_name: String) -> void:
	_player_name = player_name
	if _discovery.start_listening() != OK:
		_join.set_notice("No se pudo buscar salas automáticamente: escribe la dirección del anfitrión.")
	_show(Screen.JOIN)
	_next_room_refresh_ms = 0


func _on_join_back() -> void:
	_discovery.stop_listening()
	if _client != null:
		_client.leave()
		_client = null
	_show(Screen.MENU)


## Accepts "192.168.1.23" or "192.168.1.23:47891".
func _on_manual_address(text: String) -> void:
	var parts := text.split(":")
	var address := parts[0].strip_edges()
	var port := NetProtocol.GAME_PORT
	if parts.size() == 2 and parts[1].is_valid_int():
		port = int(parts[1])
	if parts.size() > 2 or not address.is_valid_ip_address() or port < 1024 or port > 65535:
		_join.set_notice("Escribe una dirección válida, por ejemplo 192.168.1.23")
		return
	_connect_to(address, port)


func _connect_to(address: String, port: int) -> void:
	if _client != null:
		return  # already connecting
	var client := RoomClient.new()
	if client.connect_to(address, port, _player_name) != OK:
		_join.set_notice("No se pudo conectar con esa dirección.")
		return
	_client = client
	_join.set_notice("Conectando…", false)
	client.joined.connect(_on_client_joined)
	client.join_failed.connect(_on_client_join_failed)
	client.roster_changed.connect(func(_players: Array, _phase: int, _round: int) -> void: _on_client_roster())
	client.scoreboard_changed.connect(func(board: Array) -> void: scoreboard_updated.emit(board, _my_id))
	client.round_started.connect(_on_round_started)
	client.round_finished.connect(_on_round_finished)
	client.room_closed.connect(_on_room_closed)


func _on_client_joined(_final_name: String, _room_name: String) -> void:
	_discovery.stop_listening()
	role = Role.CLIENT
	_my_id = _client.my_id
	_show(Screen.LOBBY)


func _on_client_join_failed(reason: String) -> void:
	_client = null
	_join.set_notice(join_failure_text(reason))


static func join_failure_text(reason: String) -> String:
	match reason:
		"room_full":
			return "La sala está llena."
		"round_in_progress":
			return "La partida ya empezó. Espera a que termine la ronda e inténtalo otra vez."
		"version":
			return "Esa sala usa otra versión del juego."
		"unreachable":
			return "No se encontró esa sala. Revisa la dirección y que estés en la misma red wifi."
	return "No se pudo entrar a la sala."


func _on_client_roster() -> void:
	if screen == Screen.LOBBY:
		_refresh_lobby()


func _on_room_closed(reason: String) -> void:
	_save_history()
	_client = null
	role = Role.NONE
	var text := "El anfitrión cerró la sala." if reason == "host_left" \
		else "Se perdió la conexión con el anfitrión."
	if screen == Screen.RESULTS:
		_results.set_room_closed(text)  # the host closed right after the last round: keep the results
		return
	_show(Screen.NONE)
	_dialog_action = DialogAction.ROOM_CLOSED
	_dialog.ask("Sala cerrada", text)


# --- Lobby, rounds and results ------------------------------------------------------------

func _refresh_lobby() -> void:
	var data := {}
	if role == Role.HOST and _host != null:
		data = {
			"room": _host.host_name, "is_host": true, "my_id": _my_id, "host_id": _host.host_id,
			"players": _host.session.players(), "addresses": LanDiscovery.local_addresses(),
			"port": _host.port, "can_start": _host.session.can_start(),
		}
	elif _client != null:
		data = {
			"room": _client.room_name, "is_host": false, "my_id": _my_id, "host_id": RoomClient.HOST_PEER_ID,
			"players": _client.roster, "addresses": PackedStringArray(),
			"port": NetProtocol.GAME_PORT, "can_start": false,
		}
	if not data.is_empty():
		_lobby.set_data(data)


func _on_round_started(board: PackedStringArray, countdown: float, duration: float) -> void:
	_show(Screen.GAME)
	round_begins.emit(board, countdown, duration)


func _on_round_finished(ranking: Array, table: Array) -> void:
	var mine := {}
	for entry: Dictionary in ranking:
		if entry["id"] == _my_id:
			mine = entry
	var won: bool = not mine.is_empty() and mine["rank"] == 1 and mine["score"] > 0
	Feedback.round_end(won)
	var round_number: int = _host.session.round_number if _host != null else _client.round_number
	var can_continue: bool = _host != null and _host.session.can_start()
	_results.set_data(ranking, table, _my_id, round_number, role == Role.HOST, can_continue)
	_show(Screen.RESULTS)
	round_ended.emit()


# --- Leaving ------------------------------------------------------------------------------

func _ask_to_leave() -> void:
	if role == Role.NONE:
		_leave_room()  # the room is already gone: nothing to confirm
		return
	_dialog_action = DialogAction.CONFIRM_LEAVE
	var is_host := role == Role.HOST
	_dialog.ask(
		"¿Cerrar la sala?" if is_host else "¿Salir de la sala?",
		"La sala se cerrará para todos." if is_host else "Dejarás la partida.",
		"Cerrar sala" if is_host else "Salir", "Seguir")


func _on_dialog_accepted() -> void:
	var action := _dialog_action
	_dialog_action = DialogAction.NONE
	if action == DialogAction.CONFIRM_LEAVE:
		_leave_room()
	elif action == DialogAction.ROOM_CLOSED:
		left_multiplayer.emit()


func _on_dialog_cancelled() -> void:
	_dialog_action = DialogAction.NONE


func _leave_room() -> void:
	_save_history()
	if _host != null:
		_host.close()  # it keeps running a moment so the goodbye gets through; see RoomHost
		_closing_hosts.append(_host)
		_host = null
	if _client != null:
		_client.leave()
		_client = null
	role = Role.NONE
	_show(Screen.NONE)
	left_multiplayer.emit()


## Stores a summary of the session in the local history (only if a round was played).
func _save_history() -> void:
	var now := int(Time.get_unix_time_from_system())
	var entry := {}
	if role == Role.HOST and _host != null:
		entry = _host.session.history_entry(now)
	elif _client != null:
		entry = _client.history_entry(now)
	if not entry.is_empty():
		_history.add(entry)
