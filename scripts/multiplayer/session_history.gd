class_name SessionHistory
extends RefCounted
## The last multiplayer sessions played on this device, newest first. Stored as
## JSON under user://, never sent anywhere. Entries are the dictionaries built by
## RoomSession.history_entry: {"time", "rounds", "players": [{"name", "points",
## "wins"}], "winner"}.

const MAX_ENTRIES := 20
const DEFAULT_PATH := "user://multiplayer_history.json"

var _path: String
var _entries: Array = []


func _init(path: String = DEFAULT_PATH) -> void:
	_path = path
	_load()


func entries() -> Array:
	return _entries.duplicate(true)


## Adds a session at the top and drops the oldest beyond MAX_ENTRIES. Ignores
## empty or malformed entries.
func add(entry: Dictionary) -> void:
	var clean := _normalize(entry)
	if clean.is_empty():
		return
	_entries.push_front(clean)
	while _entries.size() > MAX_ENTRIES:
		_entries.pop_back()
	_save()


func clear() -> void:
	_entries.clear()
	_save()


func _load() -> void:
	if not FileAccess.file_exists(_path):
		return
	# JSON.new().parse() reports a bad file through its return code. The static
	# JSON.parse_string() would also print an engine error for a damaged file.
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(_path)) != OK or not json.data is Array:
		return  # missing or corrupted file: start empty instead of crashing
	for raw in json.data:
		if raw is Dictionary:
			var clean := _normalize(raw)
			if not clean.is_empty() and _entries.size() < MAX_ENTRIES:
				_entries.append(clean)


func _save() -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		push_warning("Cannot write history: %s" % _path)
		return
	file.store_string(JSON.stringify(_entries))


## JSON turns every number into a float: rebuild a clean entry with integers.
func _normalize(entry: Dictionary) -> Dictionary:
	if not entry.has("players") or not entry["players"] is Array:
		return {}
	var players: Array = []
	for raw in entry["players"]:
		if raw is Dictionary and raw.has("name"):
			players.append({
				"name": String(raw["name"]),
				"points": int(raw.get("points", 0)),
				"wins": int(raw.get("wins", 0)),
			})
	if players.is_empty():
		return {}
	return {
		"time": int(entry.get("time", 0)),
		"rounds": int(entry.get("rounds", 0)),
		"players": players,
		"winner": String(entry.get("winner", "")),
	}
