class_name RoomHost
extends RefCounted
## The authoritative side of a LAN room. It owns the only real RoomSession, opens the
## ENet server, turns validated messages into session calls and broadcasts the
## outcome. The host plays too (as player 1) through submit_local_word().
## Call poll() every frame.

signal roster_changed
signal scoreboard_changed(board: Array)
signal round_started(board: PackedStringArray, countdown: float, duration: float)
signal round_finished(ranking: Array, table: Array)
signal closed

## More connections than players, so a full room can still answer "room_full".
const MAX_CONNECTIONS := 12
const KICK_DELAY_MS := 400
## After close() the socket stays up this long so the goodbye reaches every client:
## Godot drops the packets a client has not read yet when its connection ends.
const CLOSE_GRACE_MS := 300
const MAX_MESSAGES_PER_SECOND := 40
const EARLY_WORD_TOLERANCE_MS := 250
const PORT_ATTEMPTS := 10

var session := RoomSession.new()
var discovery := LanDiscovery.new()
var host_id := 1
var host_name := ""
var port := 0
var round_seconds := 180.0
var countdown_seconds := 3.0
## Words that arrive this long after the clock ends are still accepted (network delay).
var grace_seconds := 1.5
var announce_enabled := true
## A connection that never says who it is gets disconnected after this long.
var join_timeout_ms := 5000
## () -> {"board": PackedStringArray, "words": Dictionary}, where words is the result
## of BoardSolver.solve for that board. Must be set before start_round().
var board_factory := Callable()

var _peer: ENetMultiplayerPeer
var _open := false
var _closing := false
var _close_at_ms := 0
var _clients := {}  # ENet peers currently connected: id -> true
var _pending := {}  # connected but not joined yet: id -> ms it connected
var _kicks := {}  # id -> ms when to disconnect it (after a rejection was sent)
var _rates := {}  # id -> {"start": ms, "count": int}
var _play_start_ms := 0
var _round_end_ms := 0
var _finish_at_ms := 0


## Opens the room and adds the host as a player. If the preferred port is busy the next
## ones are tried; the one in use is left in `port`.
func open(player_name: String, preferred_port: int = NetProtocol.GAME_PORT) -> Error:
	var last_error := ERR_CANT_CREATE
	for offset in PORT_ATTEMPTS:
		var candidate := ENetMultiplayerPeer.new()
		last_error = candidate.create_server(preferred_port + offset, MAX_CONNECTIONS)
		if last_error == OK:
			_peer = candidate
			port = preferred_port + offset
			break
	if _peer == null:
		return last_error
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)
	host_name = session.add_player(host_id, player_name)["name"]
	_open = true
	return OK


## True while the room accepts players and words (false once close() was called).
func is_open() -> bool:
	return _open and not _closing


## True once the room has completely shut down (after close(), at the end of the grace time).
func is_closed() -> bool:
	return not _open


func poll() -> void:
	if not _open:
		return
	_peer.poll()
	var now := Time.get_ticks_msec()
	while _peer.get_available_packet_count() > 0:
		var sender := _peer.get_packet_peer()
		_handle_packet(sender, _peer.get_packet(), now)
	if _closing:
		if now >= _close_at_ms:
			_finish_close()
		return
	_check_timeouts(now)
	if session.phase == RoomSession.Phase.PLAYING and now >= _finish_at_ms:
		_finish_round()
	if announce_enabled:
		discovery.announce(announcement(), now)


## What discovery announces: the room name, its port and whether it can be joined.
func announcement() -> Dictionary:
	var open_for_players := session.phase != RoomSession.Phase.PLAYING \
		and session.connected_count() < RoomSession.MAX_PLAYERS
	return NetProtocol.announce(
		host_name, port, session.connected_count(), RoomSession.MAX_PLAYERS, open_for_players)


## Starts a round on every device. Everyone gets the same board and the same countdown.
func start_round() -> bool:
	if not is_open() or not session.can_start() or not board_factory.is_valid():
		return false
	var bundle: Dictionary = board_factory.call()
	if not session.start_round(bundle["board"], bundle["words"]):
		return false
	var now := Time.get_ticks_msec()
	_play_start_ms = now + int(countdown_seconds * 1000.0)
	_round_end_ms = _play_start_ms + int(round_seconds * 1000.0)
	_finish_at_ms = _round_end_ms + int(grace_seconds * 1000.0)
	_broadcast(NetProtocol.start(session.round_number, session.board, round_seconds, countdown_seconds))
	round_started.emit(session.board, countdown_seconds, round_seconds)
	_broadcast_scores()
	return true


## Ends the round now, for everybody, instead of waiting for the clock.
func finish_now() -> bool:
	if not is_open() or session.phase != RoomSession.Phase.PLAYING:
		return false
	_finish_round()
	return true


## The host's own words go through the same checks as everybody else's.
func submit_local_word(word: String) -> Dictionary:
	return _accept_word(host_id, word, Time.get_ticks_msec())


## Seconds left of the countdown before the round starts (0 once it started).
func countdown_left() -> float:
	if session.phase != RoomSession.Phase.PLAYING:
		return 0.0
	return maxf(0.0, (_play_start_ms - Time.get_ticks_msec()) / 1000.0)


## Seconds left on the round clock (0 outside a round or during the countdown it is the full duration).
func seconds_left() -> float:
	if session.phase != RoomSession.Phase.PLAYING:
		return 0.0
	var now := Time.get_ticks_msec()
	return clampf((_round_end_ms - now) / 1000.0, 0.0, round_seconds)


## Tells everybody the room is closing. The server keeps running for CLOSE_GRACE_MS
## (keep calling poll()) so the goodbye is delivered, then shuts down and emits `closed`.
func close() -> void:
	if not _open or _closing:
		return
	_broadcast(NetProtocol.closed("host_left"))
	_closing = true
	_close_at_ms = Time.get_ticks_msec() + CLOSE_GRACE_MS


func _finish_close() -> void:
	# Mark the room closed BEFORE closing the socket: Godot reports every disconnection
	# from inside close(), and by then nothing can be sent any more.
	_open = false
	_peer.close()
	discovery.stop()
	_clients.clear()
	_pending.clear()
	closed.emit()


# --- Incoming ------------------------------------------------------------------

func _handle_packet(sender: int, bytes: PackedByteArray, now: int) -> void:
	if _closing or not _within_rate(sender, now):
		return
	var message := NetProtocol.decode(bytes)
	if message.is_empty() or not NetProtocol.is_valid_from_client(message):
		return
	var type: String = message["t"]
	if type == NetProtocol.JOIN:
		_on_join(sender, message)
	elif type == NetProtocol.WORD:
		if session.is_online(sender):
			_send(sender, NetProtocol.result(_accept_word(sender, message["w"], now)))
	elif type == NetProtocol.LEAVE:
		_player_left(sender)


func _on_join(sender: int, message: Dictionary) -> void:
	if session.has_player(sender):
		return
	_pending.erase(sender)
	if message["v"] != NetProtocol.VERSION:
		_reject(sender, "version")
		return
	var joined := session.add_player(sender, message["name"])
	if not joined["ok"]:
		_reject(sender, joined["reason"] if joined["reason"] in NetProtocol.REJECT_REASONS else "bad_request")
		return
	_send(sender, NetProtocol.welcome(sender, joined["name"], host_name, RoomSession.MAX_PLAYERS))
	_broadcast_roster()
	roster_changed.emit()


func _accept_word(player_id: int, word: String, now: int) -> Dictionary:
	var inside_clock := now >= _play_start_ms - EARLY_WORD_TOLERANCE_MS \
		and now <= _round_end_ms + int(grace_seconds * 1000.0)
	if session.phase != RoomSession.Phase.PLAYING or not inside_clock:
		return {"status": "not_playing", "points": 0, "total": 0}
	var answer := session.submit_word(player_id, word)
	if answer["status"] == "ok":
		_broadcast_scores()
	return answer


func _within_rate(peer_id: int, now: int) -> bool:
	var info: Dictionary = _rates.get(peer_id, {"start": now, "count": 0})
	if now - int(info["start"]) >= 1000:
		info = {"start": now, "count": 0}
	info["count"] += 1
	_rates[peer_id] = info
	return info["count"] <= MAX_MESSAGES_PER_SECOND


# --- Connection events -----------------------------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	_clients[peer_id] = true
	_pending[peer_id] = Time.get_ticks_msec()


func _on_peer_disconnected(peer_id: int) -> void:
	_clients.erase(peer_id)
	_pending.erase(peer_id)
	_kicks.erase(peer_id)
	_rates.erase(peer_id)
	_player_left(peer_id)


func _player_left(peer_id: int) -> void:
	if peer_id == host_id or not session.is_online(peer_id):
		return
	session.remove_player(peer_id)
	_broadcast_roster()
	roster_changed.emit()
	if session.phase == RoomSession.Phase.PLAYING:
		_broadcast_scores()


func _check_timeouts(now: int) -> void:
	for peer_id in _pending.keys():
		if now - int(_pending[peer_id]) > join_timeout_ms:
			_pending.erase(peer_id)
			_peer.disconnect_peer(peer_id)
	for peer_id in _kicks.keys():
		if now >= int(_kicks[peer_id]):
			_kicks.erase(peer_id)
			_peer.disconnect_peer(peer_id)


func _finish_round() -> void:
	var ranking := session.finish_round()
	var table := session.cumulative_table()
	_broadcast(NetProtocol.finish(ranking, table))
	round_finished.emit(ranking, table)


# --- Outgoing --------------------------------------------------------------------

func _reject(peer_id: int, reason: String) -> void:
	_send(peer_id, NetProtocol.reject(reason))
	_kicks[peer_id] = Time.get_ticks_msec() + KICK_DELAY_MS  # give the answer time to arrive


func _send(peer_id: int, message: Dictionary) -> void:
	if not _open or not _clients.has(peer_id):
		return
	# A peer that is already closing (several players leaving together) is still in
	# _clients until its disconnection event is processed: skip it instead of making
	# ENet log an error.
	var link := _peer.get_peer(peer_id)
	if link == null or link.get_state() != ENetPacketPeer.STATE_CONNECTED:
		return
	_peer.set_target_peer(peer_id)
	_peer.put_packet(NetProtocol.encode(message))


## Only to players who have joined, never to connections that are still pending.
func _broadcast(message: Dictionary) -> void:
	for entry: Dictionary in session.players():
		if entry["id"] != host_id and entry["connected"]:
			_send(entry["id"], message)


func _broadcast_roster() -> void:
	_broadcast(NetProtocol.roster(session.players(), session.phase, session.round_number))


func _broadcast_scores() -> void:
	var board := session.provisional_board()
	_broadcast(NetProtocol.scores(board))
	scoreboard_changed.emit(board)
