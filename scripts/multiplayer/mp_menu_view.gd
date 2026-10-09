class_name MpMenuView
extends MpPanel
## Entry of the multiplayer mode: the player's name and the three ways in.

signal create_requested(player_name: String)
signal join_requested(player_name: String)
signal history_requested
signal back_requested

var _name_edit: LineEdit


func _init() -> void:
	super("Multijugador", true)
	body.add_child(make_label("Juega con otras personas conectadas a la misma red wifi.", 28, true))
	body.add_child(make_label("TU NOMBRE", 22, true))
	_name_edit = make_line_edit("Escribe tu nombre", RoomSession.MAX_NAME_LENGTH)
	body.add_child(_name_edit)

	var create := make_button("Crear sala")
	create.pressed.connect(func() -> void: create_requested.emit(_chosen_name()))
	footer.add_child(create)
	var join := make_button("Unirse a una sala")
	join.pressed.connect(func() -> void: join_requested.emit(_chosen_name()))
	footer.add_child(join)
	var history := make_button("Historial", 26, 68)
	history.pressed.connect(func() -> void: history_requested.emit())
	footer.add_child(history)
	var back := make_button("Volver", 26, 68)
	back.pressed.connect(func() -> void: back_requested.emit())
	footer.add_child(back)


func show_panel() -> void:
	_name_edit.text = GameSettings.player_name
	super.show_panel()


## The cleaned name the room will use. What was typed is remembered for next time.
func _chosen_name() -> String:
	GameSettings.set_player_name(_name_edit.text.strip_edges())
	return RoomSession.sanitize_name(_name_edit.text)
