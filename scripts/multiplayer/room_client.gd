class_name RoomClient
extends RefCounted
## A device that joins somebody else's room. It connects, sends the player's name, and
## turns the host's messages into signals. Everything the host sends is validated
## first. Call poll() every frame.

signal joined(final_name: String, room_name: String)
signal join_failed(reason: String)
signal roster_changed(players: Array, phase: int, round_number: int)
signal round_started(board: PackedStringArray, countdown: float, duration: float)
signal scoreboard_changed(board: Array)
signal word_confirmed(status: String, points: int, total: int)
signal round_finished(ranking: Array, table: Array)
signal room_closed(reason: String)

enum State { IDLE, CONNECTING, WAITING_WELCOME, JOINED, CLOSED }

const CONNECT_TIMEOUT_MS := 6000
const HOST_PEER_ID := 1

var my_id := 0
var my_name := ""
var room_name := ""
var roster: Array = []
var phase := 0
var round_number := 0
## The cumulative table of the last finished round (kept to build the local history).
var last_table: Array = []

var _peer: ENetMultiplayerPeer
var _state := State.IDLE
var _wanted_name := ""
var _started_ms := 0


func state() -> State:
	return _state


## Starts connecting; the result arrives through `joined` or `join_failed`.
func connect_to(address: String, port: int, player_name: String) -> Error:
	if _state != State.IDLE and _state != State.CLOSED:
		return ERR_ALREADY_IN_USE
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address.strip_edges(), port)
	if err != OK:
		_peer = null
		return err
	_wanted_name = player_name
	_state = State.CONNECTING
	_started_ms = Time.get_ticks_msec()
	return OK


func poll() -> void:
	if _peer == null or _state == State.IDLE or _state == State.CLOSED:
		return
	_peer.poll()
	while _peer.get_available_packet_count() > 0:
		var sender := _peer.get_packet_peer()
		var bytes := _peer.get_packet()
		if sender == HOST_PEER_ID:
			_handle(NetProtocol.decode(bytes))
		if _state == State.CLOSED:
			return
	_check_connection()


func submit_word(word: String) -> void:
	if _state == State.JOINED:
		_send(NetProtocol.word(word))


## Leaves the room: tells the host, then closes the connection.
func leave() -> void:
	if _peer == null or _state == State.CLOSED:
		return
	if _state == State.JOINED:
		_send(NetProtocol.leave())
		for i in 2:
			_peer.poll()
			OS.delay_msec(20)
	_close()


## Summary for the local history, built from the last cumulative table. Empty if no
## round was finished.
func history_entry(unix_time: int) -> Dictionary:
	if last_table.is_empty() or round_number == 0:
		return {}
	var summary: Array = []
	for row: Dictionary in last_table:
		summary.append({"name": row["name"], "points": row["points"], "wins": row["wins"]})
	var winner := String(last_table[0]["name"]) if last_table[0]["points"] > 0 else ""
	return {"time": unix_time, "rounds": round_number, "players": summary, "winner": winner}


func _check_connection() -> void:
	var status := _peer.get_connection_status()
	if status == MultiplayerPeer.CONNECTION_CONNECTING:
		if Time.get_ticks_msec() - _started_ms > CONNECT_TIMEOUT_MS:
			_fail("unreachable")
	elif status == MultiplayerPeer.CONNECTION_CONNECTED:
		if _state == State.CONNECTING:
			_state = State.WAITING_WELCOME
			_send(NetProtocol.join(_wanted_name))
	else:  # disconnected
		if _state == State.CONNECTING or _state == State.WAITING_WELCOME:
			_fail("unreachable")
		elif _state == State.JOINED:
			_close()
			room_closed.emit("connection_lost")


func _handle(message: Dictionary) -> void:
	if message.is_empty():
		return
	if message.get("v") != NetProtocol.VERSION:
		if _state == State.WAITING_WELCOME:
			_fail("version")
		return
	if not NetProtocol.is_valid_from_host(message):
		return
	var type: String = message["t"]
	if type == NetProtocol.WELCOME:
		if _state == State.WAITING_WELCOME:
			my_id = message["id"]
			my_name = message["name"]
			room_name = message["room"]
			_state = State.JOINED
			joined.emit(my_name, room_name)
	elif type == NetProtocol.REJECT:
		_fail(message["reason"])
	elif _state != State.JOINED:
		return  # nothing else is meaningful before the welcome
	elif type == NetProtocol.ROSTER:
		roster = message["players"]
		phase = message["phase"]
		round_number = message["round"]
		roster_changed.emit(roster, phase, round_number)
	elif type == NetProtocol.START:
		phase = RoomSession.Phase.PLAYING
		round_number = message["round"]
		round_started.emit(PackedStringArray(message["board"]), float(message["countdown"]), float(message["duration"]))
	elif type == NetProtocol.SCORES:
		scoreboard_changed.emit(message["board"])
	elif type == NetProtocol.RESULT:
		word_confirmed.emit(message["status"], message["points"], message["total"])
	elif type == NetProtocol.FINISH:
		phase = RoomSession.Phase.RESULTS
		last_table = message["table"]
		round_finished.emit(message["ranking"], message["table"])
	elif type == NetProtocol.CLOSED:
		_close()
		room_closed.emit(message["reason"])


func _send(message: Dictionary) -> void:
	if _peer == null:
		return
	_peer.set_target_peer(HOST_PEER_ID)
	_peer.put_packet(NetProtocol.encode(message))


func _fail(reason: String) -> void:
	_close()
	join_failed.emit(reason)


func _close() -> void:
	if _peer != null:
		_peer.close()
	_state = State.CLOSED
