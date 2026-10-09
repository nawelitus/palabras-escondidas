class_name NetProtocol
extends RefCounted
## Wire format of the LAN multiplayer. Every message is a Dictionary encoded with
## var_to_bytes and carries "t" (type) and "v" (protocol version). Both ends check
## every message they receive: the other device is never trusted, so sizes, types,
## ranges and tile letters are validated before anything is used.

const VERSION := 1
const GAME_PORT := 47890
const DISCOVERY_PORT := 47891
const MAX_PACKET_BYTES := 8192
const MAX_WORD_CHARS := 20
const MAX_NAME_INPUT := 64
const MAX_WORD_LIST := 300
const MAX_REASON_CHARS := 40
const BOARD_TILES := 16

# Client -> host
const JOIN := "join"
const WORD := "word"
const LEAVE := "leave"
# Host -> client
const WELCOME := "welcome"
const REJECT := "reject"
const ROSTER := "roster"
const START := "start"
const SCORES := "scores"
const RESULT := "result"
const FINISH := "finish"
const CLOSED := "closed"
# Discovery (UDP)
const ANNOUNCE := "announce"

const REJECT_REASONS: Array[String] = ["room_full", "round_in_progress", "version", "bad_request"]


# --- Builders ----------------------------------------------------------------

static func join(player_name: String) -> Dictionary:
	return _message(JOIN, {"name": player_name})


static func word(text: String) -> Dictionary:
	return _message(WORD, {"w": text})


static func leave() -> Dictionary:
	return _message(LEAVE, {})


static func welcome(player_id: int, player_name: String, room: String, max_players: int) -> Dictionary:
	return _message(WELCOME, {"id": player_id, "name": player_name, "room": room, "max": max_players})


static func reject(reason: String) -> Dictionary:
	return _message(REJECT, {"reason": reason})


static func roster(players: Array, phase: int, round_number: int) -> Dictionary:
	return _message(ROSTER, {"players": players, "phase": phase, "round": round_number})


static func start(round_number: int, board: PackedStringArray, duration: float, countdown: float) -> Dictionary:
	return _message(START, {
		"round": round_number,
		"board": Array(board),
		"duration": duration,
		"countdown": countdown,
	})


static func scores(board: Array) -> Dictionary:
	return _message(SCORES, {"board": board})


static func result(answer: Dictionary) -> Dictionary:
	return _message(RESULT, {
		"status": answer["status"],
		"points": answer["points"],
		"total": answer["total"],
	})


static func finish(ranking: Array, table: Array) -> Dictionary:
	return _message(FINISH, {"ranking": ranking, "table": table})


static func closed(reason: String) -> Dictionary:
	return _message(CLOSED, {"reason": reason})


static func announce(room: String, port: int, players: int, max_players: int, open: bool) -> Dictionary:
	return _message(ANNOUNCE, {
		"room": room,
		"port": port,
		"players": players,
		"max": max_players,
		"open": open,
	})


# --- Encoding ------------------------------------------------------------------

static func encode(message: Dictionary) -> PackedByteArray:
	return var_to_bytes(message)


## Returns {} for an empty, oversized or undecodable packet and for anything that is
## not a Dictionary. bytes_to_var (without objects) never builds objects from the wire.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 8 or bytes.size() > MAX_PACKET_BYTES:
		return {}
	# The first four bytes of an encoded Variant tell its type. Checking them first
	# drops anything that is not a Dictionary without letting the engine log errors,
	# so a flood of junk packets cannot fill the device log.
	if (bytes.decode_u32(0) & 0xFFFF) != TYPE_DICTIONARY:
		return {}
	var value: Variant = bytes_to_var(bytes)
	if value is Dictionary:
		return value
	return {}


# --- Validation ----------------------------------------------------------------

static func is_valid_from_client(message: Dictionary) -> bool:
	if not _has_header(message):
		return false
	var type: String = message["t"]
	if type == JOIN:
		return _is_text(message.get("name"), MAX_NAME_INPUT)
	if type == WORD:
		return _is_text(message.get("w"), MAX_WORD_CHARS)
	return type == LEAVE


static func is_valid_from_host(message: Dictionary) -> bool:
	if not _has_header(message):
		return false
	var type: String = message["t"]
	if type == WELCOME:
		return _is_int(message.get("id")) \
			and _is_name(message.get("name")) \
			and _is_name(message.get("room")) \
			and _int_in(message.get("max"), 2, RoomSession.MAX_PLAYERS)
	if type == REJECT:
		return message.get("reason") in REJECT_REASONS
	if type == ROSTER:
		return _player_list(message.get("players")) \
			and _int_in(message.get("phase"), 0, 2) \
			and _int_in(message.get("round"), 0, 10000)
	if type == START:
		return _int_in(message.get("round"), 1, 10000) \
			and _is_board(message.get("board")) \
			and _number_in(message.get("duration"), 0.1, 600.0) \
			and _number_in(message.get("countdown"), 0.0, 10.0)
	if type == SCORES:
		return _score_list(message.get("board"))
	if type == RESULT:
		return _is_text(message.get("status"), MAX_REASON_CHARS) \
			and _int_in(message.get("points"), 0, 100000) \
			and _int_in(message.get("total"), 0, 100000)
	if type == FINISH:
		return _ranking_list(message.get("ranking")) and _table_list(message.get("table"))
	if type == CLOSED:
		return _is_text(message.get("reason"), MAX_REASON_CHARS)
	return false


static func is_valid_announce(message: Dictionary) -> bool:
	return _has_header(message) \
		and message["t"] == ANNOUNCE \
		and message["v"] == VERSION \
		and _is_name(message.get("room")) \
		and _int_in(message.get("port"), 1024, 65535) \
		and _int_in(message.get("players"), 0, RoomSession.MAX_PLAYERS) \
		and _int_in(message.get("max"), 2, RoomSession.MAX_PLAYERS) \
		and message.get("open") is bool


# --- Internals -----------------------------------------------------------------

static func _message(type: String, fields: Dictionary) -> Dictionary:
	var message := {"t": type, "v": VERSION}
	message.merge(fields)
	return message


static func _has_header(message: Dictionary) -> bool:
	return message.get("t") is String and _is_int(message.get("v"))


static func _is_int(value: Variant) -> bool:
	return typeof(value) == TYPE_INT


static func _int_in(value: Variant, low: int, high: int) -> bool:
	return _is_int(value) and value >= low and value <= high


static func _number_in(value: Variant, low: float, high: float) -> bool:
	var kind := typeof(value)
	return (kind == TYPE_FLOAT or kind == TYPE_INT) and value >= low and value <= high


static func _is_text(value: Variant, max_chars: int) -> bool:
	return value is String and value.length() <= max_chars


static func _is_name(value: Variant) -> bool:
	return _is_text(value, RoomSession.MAX_NAME_LENGTH)


static func _is_board(value: Variant) -> bool:
	if not value is Array or value.size() != BOARD_TILES:
		return false
	for tile in value:
		if not tile is String or not BoardGenerator.WEIGHTS.has(tile):
			return false
	return true


static func _word_list(value: Variant) -> bool:
	if not value is Array or value.size() > MAX_WORD_LIST:
		return false
	for item in value:
		if not _is_text(item, MAX_WORD_CHARS):
			return false
	return true


static func _player_list(value: Variant) -> bool:
	if not value is Array or value.size() > RoomSession.MAX_PLAYERS:
		return false
	for entry in value:
		if not entry is Dictionary \
				or not _is_int(entry.get("id")) \
				or not _is_name(entry.get("name")) \
				or not entry.get("connected") is bool:
			return false
	return true


static func _score_list(value: Variant) -> bool:
	if not _player_list(value):
		return false
	for entry in value:
		if not _int_in(entry.get("score"), 0, 100000):
			return false
	return true


static func _ranking_list(value: Variant) -> bool:
	if not _player_list(value):
		return false
	for entry in value:
		if not _int_in(entry.get("score"), 0, 100000) \
				or not _int_in(entry.get("rank"), 1, RoomSession.MAX_PLAYERS) \
				or not _word_list(entry.get("counted")) \
				or not _word_list(entry.get("cancelled")):
			return false
	return true


static func _table_list(value: Variant) -> bool:
	if not _player_list(value):
		return false
	for entry in value:
		if not _int_in(entry.get("points"), 0, 1000000) \
				or not _int_in(entry.get("wins"), 0, 10000) \
				or not _int_in(entry.get("rounds"), 0, 10000):
			return false
	return true
