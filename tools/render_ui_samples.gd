extends Control
## Renders every multiplayer screen with sample data, in several skins, to PNG files.
## It is a scene (not a -s script) so the autoloads exist. Needs a real window:
##   godot --path . res://tools/render_ui_samples.tscn --resolution 720x1280 \
##     --rendering-driver opengl3 --quit-after 3000 -- <output folder>

const WOOD := "res://skins/wood.tres"
const COLORFUL := "res://skins/colorful.tres"
const DARK := "res://skins/dark.tres"

var _out_dir := ""
var _background := SkinBackground.new()
var _scoreboard_sample: MpScoreboard
var _count := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage: ... -- <output folder>")
		get_tree().quit(1)
		return
	_out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	add_child(_background)
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _render_all()
	print("rendered=%d" % _count)
	get_tree().quit()


func _render_all() -> void:
	await _shot("menu_wood", WOOD, _menu())
	await _shot("join_wood", WOOD, _join())
	await _shot("lobby_host_wood", WOOD, _lobby(true))
	await _shot("lobby_host_dark", DARK, _lobby(true))
	await _shot("lobby_guest_colorful", COLORFUL, _lobby(false))
	await _shot("results_wood", WOOD, _results())
	await _shot("results_dark", DARK, _results())
	await _shot("results_colorful", COLORFUL, _results())
	await _shot("history_wood", WOOD, _history())
	await _shot("dialog_wood", WOOD, _dialog())
	await _shot("scoreboard_wood", WOOD, _scoreboard())
	await _shot("scoreboard_dark", DARK, _scoreboard())


func _shot(file_name: String, skin_path: String, view: Control) -> void:
	var skin := load(skin_path) as GameSkin
	_background.set_skin(skin)
	add_child(view)
	if view is MpPanel:
		view.apply_skin(skin)
		view.show_panel()
	elif _scoreboard_sample != null:
		_scoreboard_sample.apply_skin(skin)
	for _i in 8:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	image.save_png("%s/%s.png" % [_out_dir, file_name])
	_count += 1
	view.queue_free()
	await get_tree().process_frame


func _menu() -> MpPanel:
	var view := MpMenuView.new()
	GameSettings.player_name = "Beto"
	return view


func _join() -> MpPanel:
	var view := MpJoinView.new()
	view.set_rooms([
		{"room": "Sala de Ana", "address": "192.168.1.23", "port": 47890, "players": 3, "max": 8, "open": true},
		{"room": "Carla", "address": "192.168.1.40", "port": 47890, "players": 8, "max": 8, "open": false},
		{"room": "Diego", "address": "192.168.1.51", "port": 47890, "players": 2, "max": 8, "open": false},
	])
	view.set_notice("No se encontró esa sala. Revisa la dirección y que estés en la misma red wifi.")
	return view


func _players() -> Array:
	return [
		{"id": 1, "name": "Ana", "connected": true},
		{"id": 2, "name": "Beto", "connected": true},
		{"id": 3, "name": "Carla", "connected": true},
		{"id": 4, "name": "Diego", "connected": true},
		{"id": 5, "name": "Eva", "connected": false},
	]


func _lobby(is_host: bool) -> MpPanel:
	var view := MpLobbyView.new()
	view.set_data({
		"room": "Ana", "is_host": is_host, "my_id": 1 if is_host else 2, "host_id": 1,
		"players": _players(), "addresses": PackedStringArray(["192.168.1.23"]),
		"port": NetProtocol.GAME_PORT, "can_start": true,
	})
	view.set_duration_text("Normal · 2:20")
	return view


func _results() -> MpPanel:
	var ranking := [
		{"id": 2, "name": "Beto", "connected": true, "score": 14, "rank": 1,
			"counted": ["perro", "gato", "atender", "mesa"], "cancelled": ["casa", "luna"]},
		{"id": 1, "name": "Ana", "connected": true, "score": 9, "rank": 2,
			"counted": ["escondidas", "sol"], "cancelled": ["casa"]},
		{"id": 3, "name": "Carla", "connected": true, "score": 3, "rank": 3,
			"counted": ["mar", "paz", "pan"], "cancelled": ["luna", "gato", "perro"]},
		{"id": 5, "name": "Eva", "connected": false, "score": 0, "rank": 4,
			"counted": [], "cancelled": ["casa", "sol"]},
	]
	var table := [
		{"id": 2, "name": "Beto", "connected": true, "points": 30, "wins": 2, "rounds": 3},
		{"id": 1, "name": "Ana", "connected": true, "points": 24, "wins": 1, "rounds": 3},
		{"id": 3, "name": "Carla", "connected": true, "points": 11, "wins": 0, "rounds": 3},
		{"id": 5, "name": "Eva", "connected": false, "points": 2, "wins": 0, "rounds": 2},
	]
	var view := MpResultsView.new()
	view.set_data(ranking, table, 2, 3, true, true)
	view.set_duration_text("Normal · 2:20")
	return view


func _history() -> MpPanel:
	var view := MpHistoryView.new()
	view.set_entries([
		{"time": 1791494400, "rounds": 3, "winner": "Beto",
			"players": [{"name": "Beto", "points": 30, "wins": 2}, {"name": "Ana", "points": 24, "wins": 1}, {"name": "Carla", "points": 11, "wins": 0}]},
		{"time": 1791400000, "rounds": 1, "winner": "",
			"players": [{"name": "Ana", "points": 0, "wins": 0}, {"name": "Beto", "points": 0, "wins": 0}]},
	])
	return view


func _dialog() -> MpPanel:
	var view := MpDialogView.new()
	view.ask("¿Salir de la sala?", "Dejarás la partida.", "Salir", "Seguir")
	return view


func _scoreboard() -> Control:
	var wrapper := Control.new()
	wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var board := MpScoreboard.new()
	_scoreboard_sample = board
	board.position = Vector2(24, 400)
	board.size = Vector2(672, 300)
	board.set_board([
		{"id": 1, "name": "Ana", "connected": true, "score": 9},
		{"id": 2, "name": "Beto", "connected": true, "score": 14},
		{"id": 3, "name": "Carla", "connected": true, "score": 3},
		{"id": 4, "name": "Diego", "connected": true, "score": 7},
		{"id": 5, "name": "Eva", "connected": false, "score": 2},
		{"id": 6, "name": "Franco", "connected": true, "score": 0},
		{"id": 7, "name": "Gabriela", "connected": true, "score": 5},
		{"id": 8, "name": "Hugo", "connected": true, "score": 11},
	], 2)
	wrapper.add_child(board)
	return wrapper
