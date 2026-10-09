extends SceneTree
## Headless tests for the LAN multiplayer: the wire protocol, and a real host with
## several clients talking over ENet on the loopback interface.
## Run: godot --headless --path . --quit-after 1800 -s tools/test_net.gd
## Exits with code 1 if any check fails.

const TEST_PORT := 47990
const TEST_DISCOVERY_PORT := 47995
const BOARD: Array[String] = ["e", "s", "c", "o", "d", "i", "d", "n", "a", "s", "t", "e", "l", "o", "r", "a"]
const VALID_WORDS: Array[String] = ["casa", "luna", "perro", "sol", "gato"]

var _checks := 0
var _failures := 0
var _hosts: Array[RoomHost] = []
var _probes: Array[Probe] = []
var _raw_peers: Array[ENetMultiplayerPeer] = []
var _port_offset := 0


## Records everything one client reports, so the tests can inspect it.
class Probe:
	var client := RoomClient.new()
	var joined := false
	var join_reason := ""
	var player_name := ""
	var room := ""
	var roster: Array = []
	var board := PackedStringArray()
	var scores: Array = []
	var confirmations: Array = []
	var ranking: Array = []
	var table: Array = []
	var started_count := 0
	var finished_count := 0
	var closed_reason := ""

	func _init() -> void:
		client.joined.connect(_on_joined)
		client.join_failed.connect(_on_join_failed)
		client.roster_changed.connect(_on_roster)
		client.round_started.connect(_on_started)
		client.scoreboard_changed.connect(_on_scores)
		client.word_confirmed.connect(_on_confirmed)
		client.round_finished.connect(_on_finished)
		client.room_closed.connect(_on_closed)

	func last_status() -> String:
		return "" if confirmations.is_empty() else confirmations[-1]["status"]

	func score_of(player_id: int) -> int:
		for entry: Dictionary in scores:
			if entry["id"] == player_id:
				return entry["score"]
		return -1

	func _on_joined(final_name: String, room_name: String) -> void:
		joined = true
		player_name = final_name
		room = room_name

	func _on_join_failed(reason: String) -> void:
		join_reason = reason

	func _on_roster(players: Array, _phase: int, _round: int) -> void:
		roster = players

	func _on_started(new_board: PackedStringArray, _countdown: float, _duration: float) -> void:
		board = new_board
		started_count += 1

	func _on_scores(board_scores: Array) -> void:
		scores = board_scores

	func _on_confirmed(status: String, points: int, total: int) -> void:
		confirmations.append({"status": status, "points": points, "total": total})

	func _on_finished(new_ranking: Array, new_table: Array) -> void:
		ranking = new_ranking
		table = new_table
		finished_count += 1

	func _on_closed(reason: String) -> void:
		closed_reason = reason


func _initialize() -> void:
	_test_protocol_builders_and_validators()
	_test_decode_robustness()
	_test_room_flow()
	_test_rejections()
	_test_malformed_traffic()
	_test_disconnect_and_close()
	_test_discovery()
	_reset()
	print("checks=%d failures=%d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("FAIL: %s" % label)


# --- Test plumbing -------------------------------------------------------------------

func _valid_words() -> Dictionary:
	var result := {}
	for word in VALID_WORDS:
		result[word] = [0]
	return result


func _new_host(player_name: String, round_seconds := 1.2, countdown := 0.6) -> RoomHost:
	var host := RoomHost.new()
	host.announce_enabled = false
	host.round_seconds = round_seconds
	host.countdown_seconds = countdown
	host.grace_seconds = 0.4
	host.board_factory = func() -> Dictionary:
		return {"board": PackedStringArray(BOARD), "words": _valid_words()}
	_port_offset += 12  # a fresh port range per host: no clash with a socket still closing
	var err := host.open(player_name, TEST_PORT + _port_offset)
	_check(err == OK, "host '%s' opens a port" % player_name)
	_hosts.append(host)
	return host


func _new_probe(host: RoomHost, player_name: String) -> Probe:
	var probe := Probe.new()
	_probes.append(probe)
	var err := probe.client.connect_to("127.0.0.1", host.port, player_name)
	_check(err == OK, "client '%s' starts connecting" % player_name)
	return probe


func _pump_once() -> void:
	for host in _hosts:
		host.poll()
	for probe in _probes:
		probe.client.poll()
	OS.delay_msec(4)


func _wait(condition: Callable, timeout_ms: int = 4000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		_pump_once()
		if condition.call():
			return true
	return false


func _pump_for(milliseconds: int) -> void:
	var deadline := Time.get_ticks_msec() + milliseconds
	while Time.get_ticks_msec() < deadline:
		_pump_once()


func _reset() -> void:
	for probe in _probes:
		probe.client.leave()
	for peer in _raw_peers:
		peer.close()
	for host in _hosts:
		host.close()
	_wait(func() -> bool:  # closing takes a moment so the goodbye gets through
		for host in _hosts:
			if not host.is_closed():
				return false
		return true, 3000)
	_probes.clear()
	_raw_peers.clear()
	_hosts.clear()


func _raw_client(host: RoomHost) -> ENetMultiplayerPeer:
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", host.port)
	_raw_peers.append(peer)
	var connected := _wait(func() -> bool:
		peer.poll()
		return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED)
	_check(connected, "raw peer connects")
	return peer


func _raw_send(peer: ENetMultiplayerPeer, bytes: PackedByteArray) -> void:
	peer.set_target_peer(1)
	peer.put_packet(bytes)


func _raw_replies(peer: ENetMultiplayerPeer) -> Array:
	var replies: Array = []
	peer.poll()
	while peer.get_available_packet_count() > 0:
		replies.append(NetProtocol.decode(peer.get_packet()))
	return replies


# --- Protocol ------------------------------------------------------------------------

func _test_protocol_builders_and_validators() -> void:
	_check(NetProtocol.is_valid_from_client(NetProtocol.join("Ana")), "join is valid")
	_check(NetProtocol.is_valid_from_client(NetProtocol.word("casa")), "word is valid")
	_check(NetProtocol.is_valid_from_client(NetProtocol.leave()), "leave is valid")
	_check(not NetProtocol.is_valid_from_client(NetProtocol.join("x".repeat(65))), "join name too long")
	_check(not NetProtocol.is_valid_from_client({"t": "join", "v": 1, "name": 5}), "join name not text")
	_check(not NetProtocol.is_valid_from_client(NetProtocol.word("x".repeat(21))), "word too long")
	_check(not NetProtocol.is_valid_from_client({"t": "boom", "v": 1}), "unknown type")
	_check(not NetProtocol.is_valid_from_client({"t": "join", "name": "Ana"}), "missing version")
	_check(not NetProtocol.is_valid_from_client({"t": "join", "v": "1", "name": "Ana"}), "version as text")
	_check(not NetProtocol.is_valid_from_client(NetProtocol.welcome(1, "Ana", "Room", 8)), "host message is not a client message")

	var session := RoomSession.new()
	session.add_player(1, "Ana")
	session.add_player(2, "Beto")
	session.start_round(PackedStringArray(BOARD), _valid_words())
	session.submit_word(1, "casa")
	session.submit_word(2, "casa")
	session.submit_word(2, "perro")
	var scoreboard := session.provisional_board()
	var ranking := session.finish_round()
	var table := session.cumulative_table()

	_check(NetProtocol.is_valid_from_host(NetProtocol.welcome(5, "Ana", "Room", 8)), "welcome is valid")
	_check(NetProtocol.is_valid_from_host(NetProtocol.reject("room_full")), "reject is valid")
	_check(NetProtocol.is_valid_from_host(NetProtocol.roster(session.players(), 0, 0)), "roster is valid")
	_check(NetProtocol.is_valid_from_host(NetProtocol.start(1, PackedStringArray(BOARD), 180.0, 3.0)), "start is valid")
	_check(NetProtocol.is_valid_from_host(NetProtocol.scores(scoreboard)), "scores are valid")
	_check(NetProtocol.is_valid_from_host(NetProtocol.result({"status": "ok", "points": 2, "total": 5})), "result is valid")
	_check(NetProtocol.is_valid_from_host(NetProtocol.finish(ranking, table)), "finish built from a real round is valid")
	_check(NetProtocol.is_valid_from_host(NetProtocol.closed("host_left")), "closed is valid")

	var bad_board := BOARD.duplicate()  # BOARD is a constant, so it is read-only
	bad_board.pop_back()
	var bad_tile := BOARD.duplicate()
	bad_tile[3] = "z!"
	var nine := []
	for i in 9:
		nine.append({"id": i, "name": "P", "connected": true})
	_check(not NetProtocol.is_valid_from_host({"t": "start", "v": 1, "round": 1, "board": bad_board, "duration": 180.0, "countdown": 3.0}), "board with 15 tiles")
	_check(not NetProtocol.is_valid_from_host({"t": "start", "v": 1, "round": 1, "board": bad_tile, "duration": 180.0, "countdown": 3.0}), "board with an impossible tile")
	_check(not NetProtocol.is_valid_from_host(NetProtocol.start(1, PackedStringArray(BOARD), 0.0, 3.0)), "zero duration")
	_check(not NetProtocol.is_valid_from_host(NetProtocol.start(1, PackedStringArray(BOARD), 1.0e9, 3.0)), "huge duration")
	_check(not NetProtocol.is_valid_from_host(NetProtocol.start(1, PackedStringArray(BOARD), 180.0, -1.0)), "negative countdown")
	_check(not NetProtocol.is_valid_from_host(NetProtocol.start(0, PackedStringArray(BOARD), 180.0, 3.0)), "round 0")
	_check(not NetProtocol.is_valid_from_host(NetProtocol.roster(nine, 0, 0)), "roster with 9 players")
	_check(not NetProtocol.is_valid_from_host(NetProtocol.roster([{"id": 1, "name": "x".repeat(17), "connected": true}], 0, 0)), "player name of 17 characters")
	_check(not NetProtocol.is_valid_from_host(NetProtocol.reject("weird")), "unknown reject reason")
	_check(not NetProtocol.is_valid_from_host(NetProtocol.welcome(1, "Ana", "Room", 9)), "welcome with a room for 9")
	_check(not NetProtocol.is_valid_from_host(NetProtocol.result({"status": "ok", "points": -1, "total": 0})), "negative points")
	_check(not NetProtocol.is_valid_from_host(NetProtocol.scores([{"id": 1, "name": "Ana", "connected": true, "score": -4}])), "negative score")
	var flooded: Array = []
	for i in 301:
		flooded.append("casa")
	var huge_ranking := [{"id": 1, "name": "Ana", "connected": true, "score": 1, "rank": 1, "counted": flooded, "cancelled": []}]
	_check(not NetProtocol.is_valid_from_host(NetProtocol.finish(huge_ranking, table)), "a list of 301 words")
	_check(not NetProtocol.is_valid_from_host(NetProtocol.join("Ana")), "client message is not a host message")

	_check(NetProtocol.is_valid_announce(NetProtocol.announce("Sala de Ana", 47890, 2, 8, true)), "announce is valid")
	_check(not NetProtocol.is_valid_announce(NetProtocol.announce("Sala", 80, 2, 8, true)), "announce with a privileged port")
	_check(not NetProtocol.is_valid_announce({"t": "announce", "v": 1, "room": "A", "port": 47890, "players": 1, "max": 8, "open": "yes"}), "announce with open as text")
	_check(not NetProtocol.is_valid_announce(NetProtocol.announce("x".repeat(40), 47890, 1, 8, true)), "announce with a long room name")


func _test_decode_robustness() -> void:
	var round_trip := NetProtocol.decode(NetProtocol.encode(NetProtocol.join("Ana")))
	_check(round_trip["t"] == "join" and round_trip["name"] == "Ana", "encode and decode round trip")
	_check(NetProtocol.decode(PackedByteArray()).is_empty(), "empty packet")
	var oversized := PackedByteArray()
	oversized.resize(NetProtocol.MAX_PACKET_BYTES + 1)
	_check(NetProtocol.decode(oversized).is_empty(), "oversized packet")
	_check(NetProtocol.decode(var_to_bytes([1, 2, 3])).is_empty(), "an array is not a message")
	_check(NetProtocol.decode(var_to_bytes("hello")).is_empty(), "a string is not a message")
	_check(NetProtocol.decode(PackedByteArray([1, 2, 3, 4, 5, 6, 7])).is_empty(), "garbage bytes")
	var with_object := var_to_bytes_with_objects(RefCounted.new())
	_check(NetProtocol.decode(with_object).is_empty(), "an object is never decoded from the wire")


# --- A whole room over real sockets -------------------------------------------------------

func _test_room_flow() -> void:
	var host := _new_host("Ana")
	var beto := _new_probe(host, "Beto")
	var ana2 := _new_probe(host, "ana")
	_check(_wait(func() -> bool: return beto.joined and ana2.joined), "both clients join")
	_check(beto.player_name == "Beto", "Beto keeps his name")
	_check(ana2.player_name == "ana 2", "a name equal to the host's gets a number")
	_check(beto.room == "Ana", "the client learns the room name")
	_check(_wait(func() -> bool: return beto.roster.size() == 3 and ana2.roster.size() == 3), "everybody sees the same roster")
	_check(host.session.players().size() == 3, "the host sees three players")

	_check(host.start_round(), "the host starts the round")
	_check(_wait(func() -> bool: return beto.started_count == 1 and ana2.started_count == 1), "the start reaches every client")
	_check(beto.board == host.session.board and ana2.board == host.session.board, "all devices get the same board")
	_check(beto.board.size() == 16, "16 tiles")

	beto.client.submit_word("casa")  # still inside the countdown
	_check(_wait(func() -> bool: return beto.last_status() != ""), "an early word is answered")
	_check(beto.last_status() == "not_playing", "words are refused during the countdown")

	_pump_for(500)  # the countdown (0.6 s) is over
	beto.client.submit_word("casa")
	_check(_wait(func() -> bool: return beto.last_status() == "ok"), "a valid word is accepted")
	beto.client.submit_word("casa")
	_check(_wait(func() -> bool: return beto.last_status() == "duplicate"), "the same word twice is refused")
	beto.client.submit_word("zzzz")
	_check(_wait(func() -> bool: return beto.last_status() == "invalid"), "a word that is not on the board is refused")
	beto.client.submit_word("perro")
	_check(_wait(func() -> bool: return beto.last_status() == "ok" and beto.confirmations[-1]["total"] == 4), "the total grows: casa 2 + perro 2")
	ana2.client.submit_word("casa")
	ana2.client.submit_word("luna")
	host.submit_local_word("luna")
	var local := host.submit_local_word("sol")
	_check(local["status"] == "ok", "the host plays through the same checks")
	_check(_wait(func() -> bool: return ana2.score_of(1) == 3 and ana2.score_of(ana2.client.my_id) == 4), "live scores reach every device (provisional)")
	_check(beto.score_of(beto.client.my_id) == 4, "Beto sees his provisional score")
	_check(not _live_scores_carry_words(ana2.scores), "the live board never carries words")

	_check(_wait(func() -> bool: return beto.finished_count == 1 and ana2.finished_count == 1, 5000), "the round ends on every client")
	_check(host.session.phase == RoomSession.Phase.RESULTS, "the host is in the results phase")
	var ids := []
	for entry: Dictionary in beto.ranking:
		ids.append(entry["id"])
	_check(beto.ranking[0]["name"] == "Beto" and beto.ranking[0]["score"] == 2, "Beto wins: perro is the only word nobody else found")
	_check(beto.ranking[0]["cancelled"] == ["casa"], "his casa was cancelled")
	var by_name := {}
	for entry: Dictionary in beto.ranking:
		by_name[entry["name"]] = entry
	_check(by_name["Ana"]["score"] == 1 and by_name["Ana"]["counted"] == ["sol"], "Ana keeps sol, luna is cancelled")
	_check(by_name["ana 2"]["score"] == 0, "ana 2 loses casa and luna")
	_check(by_name["ana 2"]["cancelled"].size() == 2, "two cancelled words")
	_check(ana2.ranking.size() == 3 and ana2.ranking[0]["id"] == beto.ranking[0]["id"], "every client gets the same ranking")
	_check(beto.table[0]["name"] == "Beto" and beto.table[0]["points"] == 2 and beto.table[0]["rounds"] == 1, "cumulative table after one round")
	var entry := beto.client.history_entry(1700000000)
	_check(entry["winner"] == "Beto" and entry["rounds"] == 1, "a client can build its history entry")

	_check(host.start_round(), "a second round starts from the results")
	_check(_wait(func() -> bool: return beto.started_count == 2 and ana2.started_count == 2), "round 2 reaches every client")
	_check(_wait(func() -> bool: return beto.finished_count == 2 and ana2.finished_count == 2, 5000), "round 2 ends")
	_check(beto.client.round_number == 2 and beto.table[0]["rounds"] == 2, "the table accumulates rounds")

	# The host can end a round before the clock does.
	host.round_seconds = 30.0
	_check(host.start_round(), "a third round starts")
	_check(_wait(func() -> bool: return beto.started_count == 3 and ana2.started_count == 3), "round 3 reaches every client")
	_pump_for(700)  # the countdown is over, the round is far from over
	_check(host.finish_now(), "the host ends the round early")
	_check(_wait(func() -> bool: return beto.finished_count == 3 and ana2.finished_count == 3, 1500), "the early finish reaches every client at once")
	_check(not host.finish_now(), "there is nothing left to end")
	_reset()


func _live_scores_carry_words(board: Array) -> bool:
	for entry: Dictionary in board:
		if entry.has("words") or entry.has("counted") or entry.has("cancelled"):
			return true
	return false


func _test_rejections() -> void:
	# A full room: the host plus seven clients, then a ninth player.
	var full := _new_host("Host")
	var seven: Array[Probe] = []
	for i in 7:
		seven.append(_new_probe(full, "J%d" % i))
	_check(_wait(func() -> bool:
		for probe in seven:
			if not probe.joined:
				return false
		return true), "seven clients fill the room")
	var ninth := _new_probe(full, "Extra")
	_check(_wait(func() -> bool: return ninth.join_reason != ""), "the ninth player gets an answer")
	_check(ninth.join_reason == "room_full", "the answer is room_full")
	_check(ninth.client.state() == RoomClient.State.CLOSED, "the rejected client is closed")
	_check(full.session.connected_count() == 8, "the room still has 8 players")
	_reset()

	# Joining while a round is running.
	var running := _new_host("Host")
	var first := _new_probe(running, "Uno")
	_check(_wait(func() -> bool: return first.joined), "a client joins")
	_check(running.start_round(), "the round starts")
	var late := _new_probe(running, "Tarde")
	_check(_wait(func() -> bool: return late.join_reason != ""), "a late client gets an answer")
	_check(late.join_reason == "round_in_progress", "the answer is round_in_progress")
	_reset()

	# A client that speaks another protocol version.
	var strict := _new_host("Host")
	var raw := _raw_client(strict)
	_raw_send(raw, NetProtocol.encode({"t": "join", "v": 999, "name": "Viejo"}))
	var rejected := _wait(func() -> bool:
		for reply in _raw_replies(raw):
			if reply.get("t") == "reject" and reply.get("reason") == "version":
				return true
		return false)
	_check(rejected, "another protocol version is rejected with 'version'")
	_check(strict.session.players().size() == 1, "and it never entered the room")
	_reset()

	# Names are cleaned on the way in.
	var tidy := _new_host("Host")
	var messy := _new_probe(tidy, "  Zoe \n\t Lopez  ")
	_check(_wait(func() -> bool: return messy.joined), "a messy name still joins")
	_check(messy.player_name == "Zoe Lopez", "the name is cleaned by the host")
	_reset()


func _test_malformed_traffic() -> void:
	var host := _new_host("Host")
	var raw := _raw_client(host)
	_raw_send(raw, PackedByteArray([9, 9, 9, 9, 9]))
	var oversized := PackedByteArray()
	oversized.resize(9000)
	oversized.fill(7)
	_raw_send(raw, oversized)
	_raw_send(raw, NetProtocol.encode({"t": "word"}))
	_raw_send(raw, NetProtocol.encode({"t": "join", "v": 1, "name": 123}))
	_raw_send(raw, NetProtocol.encode(NetProtocol.word("casa")))  # a word before joining
	_pump_for(300)
	_check(host.session.players().size() == 1, "malformed packets add nobody")
	_raw_send(raw, NetProtocol.encode(NetProtocol.join("Real")))
	var welcomed := _wait(func() -> bool:
		for reply in _raw_replies(raw):
			if reply.get("t") == "welcome":
				return true
		return false)
	_check(welcomed, "after the garbage a valid join still works")
	_check(host.session.players().size() == 2, "the real player is in")

	for i in 120:  # flood: the host must drop the excess and keep running
		_raw_send(raw, NetProtocol.encode(NetProtocol.word("casa")))
	_pump_for(300)
	var after := _new_probe(host, "Despues")
	_check(_wait(func() -> bool: return after.joined), "the host still serves new players after a flood")

	host.join_timeout_ms = 500
	var silent := _raw_client(host)
	var dropped := _wait(func() -> bool:
		silent.poll()
		return silent.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED, 3000)
	_check(dropped, "a connection that never introduces itself is dropped")
	_reset()


func _test_disconnect_and_close() -> void:
	var host := _new_host("Ana", 3.0, 0.3)
	var beto := _new_probe(host, "Beto")
	var carla := _new_probe(host, "Carla")
	_check(_wait(func() -> bool: return beto.joined and carla.joined), "two clients join")
	_check(host.start_round(), "round starts")
	_check(_wait(func() -> bool: return beto.started_count == 1 and carla.started_count == 1), "both start")
	_pump_for(350)
	carla.client.submit_word("sol")
	_check(_wait(func() -> bool: return carla.last_status() == "ok"), "Carla scores before leaving")
	var carla_id := carla.client.my_id
	carla.client.leave()
	_check(_wait(func() -> bool: return not host.session.is_online(carla_id)), "the host notices she left")
	_check(_wait(func() -> bool:
		for entry: Dictionary in beto.scores:
			if entry["id"] == carla_id:
				return not entry["connected"]
		return false), "the other clients see her as disconnected")
	_check(_wait(func() -> bool: return beto.finished_count == 1, 6000), "the round still finishes")
	var carla_entry := {}
	for entry: Dictionary in beto.ranking:
		if entry["id"] == carla_id:
			carla_entry = entry
	_check(carla_entry["counted"] == ["sol"] and not carla_entry["connected"], "her word counts and she is marked disconnected")

	host.close()
	_check(_wait(func() -> bool: return beto.closed_reason != ""), "closing the room is noticed by the clients")
	_check(beto.closed_reason == "host_left", "closing the room tells the clients why (got '%s')" % beto.closed_reason)
	_check(beto.client.state() == RoomClient.State.CLOSED, "the client is closed afterwards")
	_check(not host.is_open(), "a closing room no longer accepts anything")
	_check(_wait(func() -> bool: return host.is_closed()), "the host finishes shutting down")
	_reset()


func _test_discovery() -> void:
	var host := _new_host("Sala de Ana")
	host.announce_enabled = true
	host.discovery.port = TEST_DISCOVERY_PORT
	host.discovery.targets = PackedStringArray(["127.0.0.1"])
	var listener := LanDiscovery.new()
	listener.port = TEST_DISCOVERY_PORT
	_check(listener.start_listening() == OK, "the listener binds its port")
	var found := _wait(func() -> bool:
		listener.poll(Time.get_ticks_msec())
		return not listener.rooms(Time.get_ticks_msec()).is_empty())
	_check(found, "the listener hears the host's announcement")
	var rooms := listener.rooms(Time.get_ticks_msec())
	_check(rooms[0]["room"] == "Sala de Ana" and rooms[0]["port"] == host.port, "room name and port are announced")
	_check(rooms[0]["address"] == "127.0.0.1" and rooms[0]["open"] and rooms[0]["players"] == 1, "address, openness and player count")
	_check(listener.rooms(Time.get_ticks_msec() + 10000).is_empty(), "a room that stops announcing expires")
	# That call dropped the room, so wait for the host's next announcement (every second).
	_check(_wait(func() -> bool:
		listener.poll(Time.get_ticks_msec())
		return listener.rooms(Time.get_ticks_msec()).size() == 1, 3000), "the room comes back with the next announcement")

	var noise := PacketPeerUDP.new()
	noise.set_dest_address("127.0.0.1", TEST_DISCOVERY_PORT)
	noise.put_packet(PackedByteArray([1, 2, 3]))
	noise.put_packet(NetProtocol.encode(NetProtocol.announce("Trampa", 80, 1, 8, true)))
	_pump_for(150)
	listener.poll(Time.get_ticks_msec())
	_check(listener.rooms(Time.get_ticks_msec()).size() == 1, "invalid announcements are ignored")
	noise.close()
	listener.stop()

	var broadcast := LanDiscovery.broadcast_addresses()
	_check(broadcast.has("255.255.255.255"), "the limited broadcast address is always used")
	for address in broadcast:
		_check(address.ends_with(".255"), "broadcast address %s ends in .255" % address)
	for address in LanDiscovery.local_addresses():
		_check(not address.begins_with("127.") and address.split(".").size() == 4, "local address %s is a usable IPv4" % address)
	_reset()
