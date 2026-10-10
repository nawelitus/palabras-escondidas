class_name MpResultsView
extends MpPanel
## The end of a round: the ranking after cancellations, the words of the selected
## player (the ones that counted and the struck-out ones found by several players),
## and the cumulative table of the room.

signal next_round_requested
signal duration_requested
signal leave_requested

## Words found by several players: yellow text under a red line (readable on every skin).
const CANCELLED_COLOR := Color("ffd93d")
const STRIKE_COLOR := Color("e5383b")

var _ranking: Array = []
var _table: Array = []
var _my_id := 0
var _round := 0
var _is_host := false
var _can_continue := false
var _selected_id := 0
var _closed_text := ""
var _next_button: Button
var _duration_button: Button
var _leave_button: Button


func _init() -> void:
	super("Resultados")
	_next_button = make_button("Nueva ronda", 36, 92)
	_next_button.pressed.connect(func() -> void: next_round_requested.emit())
	footer.add_child(_next_button)
	_duration_button = make_button("", 26, 72)
	_duration_button.pressed.connect(func() -> void: duration_requested.emit())
	footer.add_child(_duration_button)
	_leave_button = make_button("Salir de la sala", 28, 72)
	_leave_button.pressed.connect(func() -> void: leave_requested.emit())
	footer.add_child(_leave_button)


## ranking and table come from the host's `finish` message. can_continue: the host
## still has enough connected players for another round.
func set_data(ranking: Array, table: Array, my_id: int, round_number: int, is_host: bool, can_continue: bool) -> void:
	_ranking = ranking
	_table = table
	_my_id = my_id
	_round = round_number
	_is_host = is_host
	_can_continue = can_continue
	_selected_id = my_id
	_closed_text = ""
	if visible:
		_render()


## The round length for the next round, e.g. "Normal · 2:20" (the host can change it here).
func set_duration_text(text: String) -> void:
	_duration_button.text = "Duración: " + text


## The room is gone but the results stay on screen so they can still be read.
func set_room_closed(text: String) -> void:
	_closed_text = text
	_render()


## Updates only the buttons' state, when players leave while the results are shown.
func set_can_continue(value: bool) -> void:
	_can_continue = value
	_render_footer()


func _render() -> void:
	title_label.text = "Ronda %d" % _round
	_render_footer()
	clear_children(body)
	if not _closed_text.is_empty():
		var notice := make_dynamic_label(_closed_text, 26, false)
		notice.add_theme_color_override("font_color", current_skin().danger_color)
		body.add_child(notice)
	body.add_child(make_dynamic_label("RANKING", 22, true))
	for entry: Dictionary in _ranking:
		body.add_child(_ranking_row(entry))
	body.add_child(make_dynamic_label("Toca un jugador para ver sus palabras.", 22, true))

	var selected := _entry_of(_selected_id)
	if not selected.is_empty():
		body.add_child(make_dynamic_label("PALABRAS DE %s" % String(selected["name"]).to_upper(), 22, true))
		body.add_child(_words_text(selected))
		body.add_child(make_dynamic_label("Las palabras amarillas y tachadas las encontró más de un jugador y no suman puntos.", 22, true))

	body.add_child(make_dynamic_label("ACUMULADO DE LA SALA", 22, true))
	for row: Dictionary in _table:
		var wins := "%d %s" % [row["wins"], "victoria" if row["wins"] == 1 else "victorias"]
		var text := "%s — %d pts · %s" % [row["name"], row["points"], wins]
		body.add_child(make_row(text, row["id"] == _my_id, not row["connected"], 26))


func _render_footer() -> void:
	_next_button.visible = _is_host and _closed_text.is_empty()
	_next_button.disabled = not _can_continue
	_duration_button.visible = _next_button.visible
	if not _closed_text.is_empty():
		_leave_button.text = "Salir"
	else:
		_leave_button.text = "Cerrar sala" if _is_host else "Salir de la sala"


func _ranking_row(entry: Dictionary) -> Control:
	var mine: bool = entry["id"] == _my_id
	var text := "%d. %s — %d pts" % [entry["rank"], entry["name"], entry["score"]]
	if mine:
		text += " · tú"
	if not entry["connected"]:
		text += " · desconectado"
	var button := make_dynamic_button(text, 30, 70)
	var selected: bool = entry["id"] == _selected_id
	var skin := current_skin()
	button.add_theme_stylebox_override("normal", UiStyle.row(skin, selected))
	button.add_theme_stylebox_override("hover", UiStyle.row(skin, selected))
	button.add_theme_stylebox_override("pressed", UiStyle.row(skin, true))
	button.add_theme_color_override("font_color", skin.text_color)
	button.add_theme_color_override("font_hover_color", skin.text_color)
	button.add_theme_color_override("font_pressed_color", skin.text_color)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var player_id: int = entry["id"]
	button.pressed.connect(func() -> void:
		_selected_id = player_id
		_render())
	return button


## The words of one player, wrapped over several lines. The ones that counted use the
## skin's text color; the cancelled ones are yellow with a red line through them, so it
## is obvious they were discounted.
func _words_text(entry: Dictionary) -> Control:
	var skin := current_skin()
	var flow := HFlowContainer.new()
	flow.mouse_filter = Control.MOUSE_FILTER_PASS
	flow.add_theme_constant_override("h_separation", 22)
	flow.add_theme_constant_override("v_separation", 4)
	for word: String in entry["counted"]:
		flow.add_child(_word_label(word, skin.text_color))
	for word: String in entry["cancelled"]:
		var label := _word_label(word, CANCELLED_COLOR)
		var line := ColorRect.new()
		line.color = STRIKE_COLOR
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.anchor_left = 0.0
		line.anchor_right = 1.0
		line.anchor_top = 0.5
		line.anchor_bottom = 0.5
		line.offset_left = -4.0
		line.offset_right = 4.0
		line.offset_top = -2.0
		line.offset_bottom = 2.0
		label.add_child(line)
		flow.add_child(label)
	if flow.get_child_count() == 0:
		flow.add_child(_word_label("Ninguna palabra.", skin.text_color, false))
	return flow


func _word_label(word: String, color: Color, upper := true) -> Label:
	var label := Label.new()
	label.text = word.to_upper() if upper else word
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", color)
	return label


func _entry_of(player_id: int) -> Dictionary:
	for entry: Dictionary in _ranking:
		if entry["id"] == player_id:
			return entry
	return {}
