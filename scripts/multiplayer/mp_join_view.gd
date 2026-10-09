class_name MpJoinView
extends MpPanel
## Lists the rooms heard on the network, and lets the player type the host's address
## when discovery does not work (some networks block it).

signal room_chosen(address: String, port: int)
signal manual_requested(address: String)
signal back_requested

var _rooms: Array = []
var _rooms_signature := ""
var _status_label: Label
var _notice_label: Label
var _notice_is_error := false
var _list := VBoxContainer.new()
var _address_edit: LineEdit


func _init() -> void:
	super("Unirse a una sala")
	_status_label = make_label("", 26, true)
	body.add_child(_status_label)
	_notice_label = make_dynamic_label("", 26, false)  # keeps its own color (error or progress)
	_notice_label.visible = false
	body.add_child(_notice_label)
	_list.add_theme_constant_override("separation", 10)
	body.add_child(_list)

	body.add_child(make_label("¿No aparece tu sala? Escribe la dirección que muestra el anfitrión:", 24, true))
	_address_edit = make_line_edit("192.168.1.23", 21)
	body.add_child(_address_edit)
	var connect_button := make_button("Conectar", 30, 76)
	connect_button.pressed.connect(func() -> void: manual_requested.emit(_address_edit.text.strip_edges()))
	body.add_child(connect_button)

	var back := make_button("Volver", 28, 72)
	back.pressed.connect(func() -> void: back_requested.emit())
	footer.add_child(back)


## rooms: the result of LanDiscovery.rooms(). The list is only rebuilt when it changes.
func set_rooms(rooms: Array) -> void:
	var signature := ""
	for room: Dictionary in rooms:
		signature += "%s:%d:%d:%s|" % [room["address"], room["port"], room["players"], room["open"]]
	if signature == _rooms_signature:
		return
	_rooms_signature = signature
	_rooms = rooms
	if _notice_is_error:
		set_notice("")  # the list moved on: an old problem would only confuse
	if visible:
		_render()


## A message under the room list: a problem ("No se pudo conectar", in the danger
## color) or progress ("Conectando…"). An empty text hides it.
func set_notice(text: String, is_error: bool = true) -> void:
	_notice_label.text = text
	_notice_label.visible = not text.is_empty()
	_notice_is_error = is_error and not text.is_empty()
	var skin := current_skin()
	_notice_label.add_theme_color_override("font_color", skin.danger_color if is_error else skin.accent_color)


func _render() -> void:
	_status_label.text = "Buscando salas en tu red…" if _rooms.is_empty() \
		else "Toca una sala para unirte:"
	clear_children(_list)
	for room: Dictionary in _rooms:
		var label := "%s · %d/%d" % [room["room"], room["players"], room["max"]]
		if not room["open"]:
			label += " · " + ("llena" if room["players"] >= room["max"] else "en juego")
		var button := make_dynamic_button(label)
		button.disabled = not room["open"]
		var address: String = room["address"]
		var port: int = room["port"]
		button.pressed.connect(func() -> void: room_chosen.emit(address, port))
		_list.add_child(button)
