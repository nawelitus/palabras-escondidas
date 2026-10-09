class_name MpScoreboard
extends VBoxContainer
## Live scores of the players during a round, in two columns. The scores are
## provisional: words found by several players only cancel when the round ends.

var _caption := Label.new()
var _grid := GridContainer.new()
var _board: Array = []
var _my_id := 0
var _skin: GameSkin


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	_caption.text = "MARCADOR (PROVISORIO)"
	_caption.add_theme_font_size_override("font_size", 20)
	add_child(_caption)
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 6)
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grid)


## board: RoomSession.provisional_board() entries (id, name, connected, score).
func set_board(board: Array, my_id: int) -> void:
	_board = board
	_my_id = my_id
	_render()


func apply_skin(skin: GameSkin) -> void:
	_skin = skin
	_caption.add_theme_color_override("font_color", skin.text_dim_color)
	_render()


func _render() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	if _skin == null:
		return
	var ordered := _board.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["score"] > b["score"] if a["score"] != b["score"] else int(a["id"]) < int(b["id"]))
	for entry: Dictionary in ordered:
		var mine: bool = entry["id"] == _my_id
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_theme_stylebox_override("panel", UiStyle.row(_skin, mine))
		var label := Label.new()
		label.text = "%s   %d" % [entry["name"], entry["score"]]
		label.clip_text = true
		label.add_theme_font_size_override("font_size", 24)
		label.add_theme_color_override("font_color", _skin.text_dim_color if not entry["connected"] else _skin.text_color)
		cell.add_child(label)
		_grid.add_child(cell)
