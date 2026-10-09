class_name MpHistoryView
extends MpPanel
## The last multiplayer sessions played on this device.

signal back_requested

var _entries: Array = []


func _init() -> void:
	super("Historial")
	var back := make_button("Volver", 28, 72)
	back.pressed.connect(func() -> void: back_requested.emit())
	footer.add_child(back)


## entries: SessionHistory.entries(), newest first.
func set_entries(entries: Array) -> void:
	_entries = entries
	if visible:
		_render()


## "08/10/2026 21:37" in the device's own time zone.
static func format_time(unix_time: int) -> String:
	var bias_minutes: int = Time.get_time_zone_from_system()["bias"]
	var local := Time.get_datetime_dict_from_unix_time(unix_time + bias_minutes * 60)
	return "%02d/%02d/%04d %02d:%02d" % [local["day"], local["month"], local["year"], local["hour"], local["minute"]]


func _render() -> void:
	clear_children(body)
	if _entries.is_empty():
		body.add_child(make_dynamic_label("Todavía no jugaste partidas multijugador.", 28, true))
		return
	body.add_child(make_dynamic_label("PARTIDAS RECIENTES (se guardan hasta %d)" % SessionHistory.MAX_ENTRIES, 22, true))
	for entry: Dictionary in _entries:
		var rounds: int = entry["rounds"]
		var head := "%s · %d %s" % [format_time(entry["time"]), rounds, "ronda" if rounds == 1 else "rondas"]
		var lines := PackedStringArray([head])
		lines.append("Ganó: %s" % entry["winner"] if entry["winner"] != "" else "Sin ganador")
		var people := PackedStringArray()
		for person: Dictionary in entry["players"]:
			people.append("%s %d" % [person["name"], person["points"]])
		lines.append(", ".join(people))
		body.add_child(make_row("\n".join(lines), false, false, 24))
