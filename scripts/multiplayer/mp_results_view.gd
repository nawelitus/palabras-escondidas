class_name MpResultsView
extends MpPanel
## The end of a round: the ranking after cancellations, the words of the selected
## player (the ones that counted and the struck-out ones found by several players),
## and the cumulative table of the room.

signal next_round_requested
signal leave_requested

var _ranking: Array = []
var _table: Array = []
var _my_id := 0
var _round := 0
var _is_host := false
var _can_continue := false
var _selected_id := 0
var _next_button: Button
var _leave_button: Button


func _init() -> void:
	super("Resultados")
	_next_button = make_button("Nueva ronda", 36, 92)
	_next_button.pressed.connect(func() -> void: next_round_requested.emit())
	footer.add_child(_next_button)
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
	if visible:
		_render()


## Updates only the buttons' state, when players leave while the results are shown.
func set_can_continue(value: bool) -> void:
	_can_continue = value
	_render_footer()


func _render() -> void:
	title_label.text = "Ronda %d" % _round
	_render_footer()
	clear_children(body)
	body.add_child(make_dynamic_label("RANKING", 22, true))
	for entry: Dictionary in _ranking:
		body.add_child(_ranking_row(entry))
	body.add_child(make_dynamic_label("Toca un jugador para ver sus palabras.", 22, true))

	var selected := _entry_of(_selected_id)
	if not selected.is_empty():
		body.add_child(make_dynamic_label("PALABRAS DE %s" % String(selected["name"]).to_upper(), 22, true))
		body.add_child(_words_text(selected))
		body.add_child(make_dynamic_label("Las palabras tachadas las encontró más de un jugador y no suman puntos.", 22, true))

	body.add_child(make_dynamic_label("ACUMULADO DE LA SALA", 22, true))
	for row: Dictionary in _table:
		var wins := "%d %s" % [row["wins"], "victoria" if row["wins"] == 1 else "victorias"]
		var text := "%s — %d pts · %s" % [row["name"], row["points"], wins]
		body.add_child(make_row(text, row["id"] == _my_id, not row["connected"], 26))


func _render_footer() -> void:
	_next_button.visible = _is_host
	_next_button.disabled = not _can_continue
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


func _words_text(entry: Dictionary) -> RichTextLabel:
	var skin := current_skin()
	var parts := PackedStringArray()
	for word: String in entry["counted"]:
		parts.append(word.to_upper())
	var dim := skin.text_dim_color.to_html(false)
	for word: String in entry["cancelled"]:
		parts.append("[color=#%s][s]%s[/s][/color]" % [dim, word.to_upper()])
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("normal_font_size", 26)
	label.add_theme_color_override("default_color", skin.text_color)
	label.text = "   ".join(parts) if not parts.is_empty() else "Ninguna palabra."
	return label


func _entry_of(player_id: int) -> Dictionary:
	for entry: Dictionary in _ranking:
		if entry["id"] == player_id:
			return entry
	return {}
