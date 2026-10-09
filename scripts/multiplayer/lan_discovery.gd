class_name LanDiscovery
extends RefCounted
## Finds rooms on the same network. A host announces itself by UDP broadcast once a
## second; a device that is searching listens and keeps the rooms heard recently.
## Some routers and guest networks block broadcast, so joining by typing the host's
## address must always stay available as a fallback.

const ANNOUNCE_INTERVAL_MS := 1000
const ROOM_TTL_MS := 3500

var port := NetProtocol.DISCOVERY_PORT
## Where announcements are sent. Empty means the broadcast addresses of this
## device's networks (tests point it at 127.0.0.1).
var targets := PackedStringArray()

var _sender := PacketPeerUDP.new()
var _listener: PacketPeerUDP
var _rooms := {}  # "address:port" -> {"room", "address", "port", "players", "max", "open", "seen"}
var _next_announce_ms := 0


## Broadcast addresses of the networks this device is on, assuming /24 subnets (home
## WiFi and phone hotspots), plus the limited broadcast address.
static func broadcast_addresses() -> PackedStringArray:
	var result := PackedStringArray(["255.255.255.255"])
	for address in local_addresses():
		var parts := address.split(".")
		var broadcast := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
		if not result.has(broadcast):
			result.append(broadcast)
	return result


## IPv4 addresses of this device on its networks (loopback and link-local excluded):
## the host shows them so other players can type one if discovery does not work.
static func local_addresses() -> PackedStringArray:
	var result := PackedStringArray()
	for address in IP.get_local_addresses():
		var parts := address.split(".")
		if parts.size() != 4 or address.begins_with("127.") or address.begins_with("169.254."):
			continue
		if not result.has(address):
			result.append(address)
	return result


func announce(announcement: Dictionary, now_ms: int) -> void:
	if now_ms < _next_announce_ms:
		return
	_next_announce_ms = now_ms + ANNOUNCE_INTERVAL_MS
	var bytes := NetProtocol.encode(announcement)
	_sender.set_broadcast_enabled(true)
	for address in (targets if not targets.is_empty() else broadcast_addresses()):
		if _sender.set_dest_address(address, port) == OK:
			_sender.put_packet(bytes)


func start_listening() -> Error:
	stop_listening()
	_listener = PacketPeerUDP.new()
	_listener.set_broadcast_enabled(true)
	var err := _listener.bind(port, "*")
	if err != OK:
		_listener = null
	return err


func stop_listening() -> void:
	if _listener != null:
		_listener.close()
		_listener = null
	_rooms.clear()


func stop() -> void:
	stop_listening()
	_sender.close()


## Reads pending announcements. Packets that are not valid announcements are dropped.
func poll(now_ms: int) -> void:
	if _listener == null:
		return
	while _listener.get_available_packet_count() > 0:
		var bytes := _listener.get_packet()
		var address := _listener.get_packet_ip()
		if _listener.get_packet_error() != OK:
			continue
		var message := NetProtocol.decode(bytes)
		if not NetProtocol.is_valid_announce(message):
			continue
		_rooms["%s:%d" % [address, message["port"]]] = {
			"room": message["room"],
			"address": address,
			"port": message["port"],
			"players": message["players"],
			"max": message["max"],
			"open": message["open"],
			"seen": now_ms,
		}


## Rooms heard in the last few seconds, by name. The address is where the packet came
## from, not a value the sender claims.
func rooms(now_ms: int) -> Array:
	var fresh: Array = []
	for key in _rooms.keys():
		if now_ms - int(_rooms[key]["seen"]) > ROOM_TTL_MS:
			_rooms.erase(key)
		else:
			fresh.append(_rooms[key].duplicate())
	fresh.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["room"]).to_lower() < String(b["room"]).to_lower())
	return fresh
