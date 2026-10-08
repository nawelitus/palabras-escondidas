class_name BoardView
extends Control
## Draws the 4x4 board and turns finger drags into words.

signal path_changed(word: String)
signal word_submitted(word: String, path: Array)
## Emitted when a tile is added to or removed from the path, with the new path size.
signal tile_selected(path_size: int)

enum Flash { NONE, OK, REPEAT, INVALID }

const SIZE := 4
## Hit area of a tile as a fraction of a cell. Under 0.5 so diagonal drags
## don't accidentally touch the neighbours' corners.
const HIT_RADIUS := 0.38
const FLASH_SECONDS := 0.45
const POP_SPEED := 6.0

## Input is accepted only while true.
var active := false
## Letters are drawn only while true (hidden before the round starts).
var revealed := false:
	set(value):
		revealed = value
		queue_redraw()

var _board := PackedStringArray()
var _skin: GameSkin
var _path: Array[int] = []
var _dragging := false
var _pop := PackedFloat32Array()
var _tilts := PackedFloat32Array()
var _flash_path: Array[int] = []
var _flash_kind := Flash.NONE
var _flash_left := 0.0
var _styles := {}


func _init() -> void:
	_pop.resize(SIZE * SIZE)
	_tilts.resize(SIZE * SIZE)


func set_board(board: PackedStringArray) -> void:
	_board = board
	_path.clear()
	_flash_path.clear()
	_flash_left = 0.0
	_dragging = false
	_pop.fill(0.0)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in _tilts.size():
		_tilts[i] = rng.randf_range(-1.0, 1.0)
	queue_redraw()


func set_skin(skin: GameSkin) -> void:
	_skin = skin
	_build_styles()
	queue_redraw()


func current_word() -> String:
	var word := ""
	for index in _path:
		word += _board[index]
	return word


## Colors the tiles of a submitted path for a moment.
func flash(path: Array, kind: Flash) -> void:
	_flash_path.clear()
	for index in path:
		_flash_path.append(index)
	_flash_kind = kind
	_flash_left = FLASH_SECONDS
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _skin != null:
		_build_styles()


func _process(delta: float) -> void:
	var dirty := false
	for i in _pop.size():
		if _pop[i] > 0.0:
			_pop[i] = maxf(0.0, _pop[i] - delta * POP_SPEED)
			dirty = true
	if _flash_left > 0.0:
		_flash_left -= delta
		dirty = true
		if _flash_left <= 0.0:
			_flash_kind = Flash.NONE
			_flash_path.clear()
	if dirty:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not active:
		return
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_begin(button.position)
		else:
			_end()
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		_extend(motion.position)
		accept_event()


func _begin(pos: Vector2) -> void:
	var index := _tile_at(pos)
	if index < 0:
		return
	_flash_left = 0.0
	_flash_path.clear()
	_dragging = true
	_path = [index]
	_pop[index] = 1.0
	path_changed.emit(current_word())
	tile_selected.emit(_path.size())
	queue_redraw()


func _extend(pos: Vector2) -> void:
	var index := _tile_at(pos)
	if index < 0 or index == _path[-1]:
		return
	if _path.size() >= 2 and index == _path[-2]:
		_path.pop_back()  # dragging back over the previous tile undoes the last one
	elif index in _path or not _are_adjacent(_path[-1], index):
		return
	else:
		_path.append(index)
		_pop[index] = 1.0
	path_changed.emit(current_word())
	tile_selected.emit(_path.size())
	queue_redraw()


func _end() -> void:
	if not _dragging:
		return
	_dragging = false
	var word := current_word()
	var path := _path.duplicate()
	_path.clear()
	path_changed.emit("")
	word_submitted.emit(word, path)
	queue_redraw()


func _are_adjacent(a: int, b: int) -> bool:
	return absi(a % SIZE - b % SIZE) <= 1 and absi(floori(a / float(SIZE)) - floori(b / float(SIZE))) <= 1


func _side() -> float:
	return minf(size.x, size.y)


func _cell() -> float:
	return _side() / SIZE


func _origin() -> Vector2:
	var side := _side()
	return Vector2((size.x - side) * 0.5, (size.y - side) * 0.5)


func _center(index: int) -> Vector2:
	var col := index % SIZE
	var row := floori(index / float(SIZE))
	return _origin() + Vector2(col + 0.5, row + 0.5) * _cell()


func _tile_at(pos: Vector2) -> int:
	var cell := _cell()
	var rel := pos - _origin()
	if rel.x < 0.0 or rel.y < 0.0:
		return -1
	var col := floori(rel.x / cell)
	var row := floori(rel.y / cell)
	if col >= SIZE or row >= SIZE:
		return -1
	var index := row * SIZE + col
	if pos.distance_to(_center(index)) > cell * HIT_RADIUS:
		return -1
	return index


func _build_styles() -> void:
	var tile_px := _cell() * (1.0 - _skin.tile_gap)
	var radius := int(tile_px * _skin.tile_radius)
	_styles = {
		"normal": _tile_style(_skin.tile_color, _skin.tile_border_color, radius),
		"selected": _tile_style(_skin.tile_selected_color, _skin.tile_selected_color.darkened(0.3), radius),
		"valid": _tile_style(_skin.tile_valid_color, _skin.tile_valid_color.darkened(0.3), radius),
		"invalid": _tile_style(_skin.tile_invalid_color, _skin.tile_invalid_color.darkened(0.3), radius),
		"repeat": _tile_style(_skin.tile_repeat_color, _skin.tile_repeat_color.darkened(0.3), radius),
	}
	var tray := StyleBoxFlat.new()
	tray.bg_color = _skin.board_color
	tray.border_color = _skin.board_border_color
	tray.set_border_width_all(3)
	tray.set_corner_radius_all(_skin.board_radius)
	tray.anti_aliasing = true
	_styles["tray"] = tray


func _tile_style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(_skin.tile_border_width)
	style.set_corner_radius_all(radius)
	style.shadow_color = _skin.tile_shadow_color
	style.shadow_size = _skin.tile_shadow_size
	style.shadow_offset = _skin.tile_shadow_offset
	style.anti_aliasing = true
	return style


func _state_for(index: int) -> String:
	if _flash_left > 0.0 and index in _flash_path:
		match _flash_kind:
			Flash.OK:
				return "valid"
			Flash.REPEAT:
				return "repeat"
			Flash.INVALID:
				return "invalid"
	if index in _path:
		return "selected"
	return "normal"


func _tile_label(tile: String) -> String:
	return "Qu" if tile == "qu" else tile.to_upper()


func _draw() -> void:
	if _skin == null or _board.size() != SIZE * SIZE:
		return
	var cell := _cell()
	draw_style_box(_styles["tray"], Rect2(_origin(), Vector2(cell, cell) * SIZE))
	var tile_px := cell * (1.0 - _skin.tile_gap)
	var half := Vector2(tile_px, tile_px) * 0.5
	var font := get_theme_default_font()
	var font_size := int(tile_px * 0.52)
	# Drawn under the tiles so it only shows in the gaps and never cuts letters.
	if _path.size() > 1:
		var points := PackedVector2Array()
		for index in _path:
			points.append(_center(index))
		draw_polyline(points, _skin.path_color, cell * 0.14, true)
	for i in _board.size():
		var state := _state_for(i)
		var tile_scale := 1.0 + _pop[i] * 0.12 + (0.05 if i in _path else 0.0)
		var tilt := deg_to_rad(_tilts[i] * _skin.tile_tilt_degrees)
		draw_set_transform(_center(i), tilt, Vector2(tile_scale, tile_scale))
		draw_style_box(_styles[state], Rect2(-half, half * 2.0))
		if revealed:
			var label := _tile_label(_board[i])
			var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var baseline := (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
			var color := _skin.tile_text_color if state == "normal" else _skin.tile_selected_text_color
			draw_string(font, Vector2(-text_size.x * 0.5, baseline), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	draw_set_transform_matrix(Transform2D.IDENTITY)
