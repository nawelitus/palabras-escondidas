class_name MpLobbyView
extends MpPanel
## The waiting room: who is in, and how to start (host) or what to wait for (guests).

signal start_requested
signal leave_requested

var _data := {
	"room": "", "is_host": false, "my_id": 0, "host_id": 1,
	"players": [], "addresses": PackedStringArray(), "port": NetProtocol.GAME_PORT,
	"can_start": false,
}
var _start_button: Button
var _leave_button: Button


func _init() -> void:
	super("Sala")
	_start_button = make_button("Iniciar partida", 36, 92)
	_start_button.pressed.connect(func() -> void: start_requested.emit())
	footer.add_child(_start_button)
	_leave_button = make_button("Salir de la sala", 28, 72)
	_leave_button.pressed.connect(func() -> void: leave_requested.emit())
	footer.add_child(_leave_button)


## data: room (name), is_host, my_id, host_id, players (RoomSession.players()),
## addresses (this device's IPv4s, shown to the host), port, can_start.
func set_data(data: Dictionary) -> void:
	_data = data
	if visible:
		_render()


func _render() -> void:
	var is_host: bool = _data["is_host"]
	title_label.text = "Sala de %s" % _data["room"]
	_start_button.visible = is_host
	_start_button.disabled = not _data["can_start"]
	_leave_button.text = "Cerrar sala" if is_host else "Salir de la sala"
	clear_children(body)

	if is_host:
		body.add_child(make_dynamic_label("Los demás pueden unirse desde «Unirse a una sala» o escribiendo esta dirección:", 24, true))
		var addresses: PackedStringArray = _data["addresses"]
		if addresses.is_empty():
			body.add_child(make_dynamic_label("No se encontró una red wifi. ¿Estás conectado?", 26, false))
		for address in addresses:
			var shown := address if _data["port"] == NetProtocol.GAME_PORT else "%s:%d" % [address, _data["port"]]
			body.add_child(make_dynamic_label(shown, 44, false))

	var players: Array = _data["players"]
	body.add_child(make_dynamic_label("JUGADORES (%d/%d)" % [players.size(), RoomSession.MAX_PLAYERS], 22, true))
	for entry: Dictionary in players:
		var text: String = entry["name"]
		if entry["id"] == _data["host_id"]:
			text += " · anfitrión"
		if entry["id"] == _data["my_id"]:
			text += " · tú"
		if not entry["connected"]:
			text += " · desconectado"
		body.add_child(make_row(text, entry["id"] == _data["my_id"], not entry["connected"], 30))

	if is_host and not _data["can_start"]:
		body.add_child(make_dynamic_label("Se necesitan al menos %d jugadores para empezar." % RoomSession.MIN_PLAYERS_TO_START, 24, true))
	elif not is_host:
		body.add_child(make_dynamic_label("Esperando que el anfitrión inicie la partida…", 26, true))
