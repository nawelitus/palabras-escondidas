extends Control
## Game flow and HUD for one timed round. All styling comes from the active GameSkin.

const DICTIONARY_PATH := "res://data/words_es.txt"
const ROUND_SECONDS := 180.0
const MIN_PLAYABLE_WORDS := 100
const LOW_TIME_SECONDS := 10.0
const MESSAGE_SECONDS := 0.9
const BOARD_SIDE := 672.0
## Space above the HUD, on top of the display's safe-area inset (notch, camera hole).
const TOP_MARGIN := 48
const GAME_TITLE := "Palabras Escondidas"
const INTRO_TEXT := "Encuentra palabras uniendo letras vecinas, también en diagonal. Tienes 3 minutos."

## Longest time step the round clock accepts in one frame. Protects the timer
## if the OS delivers a huge delta after the app comes back from the background.
const MAX_TIME_STEP := 0.25

enum State { LOADING, READY, COUNTDOWN, PLAYING, PAUSED, FINISHED }
## SOLO is the single-player round; MULTI is a round of a LAN room, whose board, clock
## and final scores come from the host through MultiplayerUi.
enum Mode { SOLO, MULTI }

var _state := State.LOADING
var _dictionary := WordDictionary.new()
var _generator := BoardGenerator.new()
var _solutions := {}
var _found: Array[String] = []
var _score := 0
var _time_left := ROUND_SECONDS
var _message_left := 0.0
var _record_at_start := 0

var _background: SkinBackground
var _board_view: BoardView
var _score_label: Label
var _timer_label: Label
var _record_label: Label
var _word_label: Label
var _found_caption: Label
var _found_flow: HFlowContainer
var _overlay: Control
var _overlay_title: Label
var _overlay_body: Label
var _play_button: Button
var _overlay_skin_button: Button
var _toggle_row: HBoxContainer
var _sound_button: Button
var _haptics_button: Button
var _credits_button: Button
var _credits: CreditsView
var _last_second := 0

var _mode := Mode.SOLO
var _mp: MultiplayerUi
var _mp_button: Button
var _scoreboard: MpScoreboard
var _record_caption: Label
var _countdown_left := 0.0
var _mp_scores: Array = []

var _panels: Array[PanelContainer] = []
var _text_labels: Array[Label] = []
var _dim_labels: Array[Label] = []
var _buttons: Array[Button] = []


func _ready() -> void:
	_build_ui()
	GameSettings.skin_changed.connect(_apply_skin)
	_apply_skin(GameSettings.current_skin())
	_show_overlay(GAME_TITLE, "Cargando diccionario…", "", false)
	# Let the loading screen render before the blocking dictionary load.
	await get_tree().process_frame
	await get_tree().process_frame
	var load_started := Time.get_ticks_msec()
	var loaded := _dictionary.load_from_file(DICTIONARY_PATH)
	if OS.is_debug_build():
		print("DEBUG dict_load_ms=%d words=%d" % [Time.get_ticks_msec() - load_started, _dictionary.size()])
	if loaded:
		_state = State.READY
		_show_overlay(GAME_TITLE, INTRO_TEXT, "Jugar", true)
	else:
		_show_overlay(GAME_TITLE, "No se pudo cargar el diccionario.", "", false)


func _process(delta: float) -> void:
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			_set_word_text("", _current_skin().text_color)
	if _state == State.COUNTDOWN:
		_run_countdown(delta)
		return
	if _state != State.PLAYING:
		return
	_time_left -= minf(delta, MAX_TIME_STEP)
	if _time_left <= 0.0:
		_time_left = 0.0
		_update_timer()
		_finish_round()
		return
	var whole_second := ceili(_time_left)
	if whole_second != _last_second:
		_last_second = whole_second
		if whole_second <= LOW_TIME_SECONDS:
			Feedback.tick()
	_update_timer()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if _mode == Mode.SOLO:  # a room's clock belongs to everybody: it never pauses
				_pause_round()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			# Android back button: close the credits, then any multiplayer screen, then pause
			# a solo round, otherwise leave the game.
			if _credits != null and _credits.visible:
				_credits.hide_credits()
			elif _mp != null and _mp.handle_back():
				pass
			elif _state == State.PLAYING:
				_pause_round()
			else:
				get_tree().quit()


# --- UI construction -------------------------------------------------------

func _build_ui() -> void:
	_background = SkinBackground.new()
	add_child(_background)
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.add_theme_constant_override("margin_top", TOP_MARGIN + int(_safe_top_inset()))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	column.add_child(bar)
	_score_label = _add_stat(bar, "PUNTOS")
	_timer_label = _add_stat(bar, "TIEMPO")
	_record_label = _add_stat(bar, "RÉCORD")
	_record_caption = _record_label.get_parent().get_child(0)  # the caption becomes "PUESTO" in a room
	var skin_button := _make_button("Estilo", 26)
	skin_button.pressed.connect(GameSettings.cycle_skin)
	bar.add_child(skin_button)

	_word_label = Label.new()
	_word_label.custom_minimum_size = Vector2(0, 84)
	_word_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_word_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_word_label.add_theme_font_size_override("font_size", 56)
	_word_label.clip_text = true
	_text_labels.append(_word_label)
	column.add_child(_word_label)

	_board_view = BoardView.new()
	_board_view.custom_minimum_size = Vector2(0, BOARD_SIDE)
	_board_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_view.path_changed.connect(_on_path_changed)
	_board_view.word_submitted.connect(_on_word_submitted)
	_board_view.tile_selected.connect(Feedback.tile_step)
	column.add_child(_board_view)

	_scoreboard = MpScoreboard.new()
	_scoreboard.visible = false
	column.add_child(_scoreboard)

	_found_caption = Label.new()
	_found_caption.add_theme_font_size_override("font_size", 22)
	_dim_labels.append(_found_caption)
	column.add_child(_found_caption)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_found_flow = HFlowContainer.new()
	_found_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_found_flow.add_theme_constant_override("h_separation", 10)
	_found_flow.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_found_flow)

	_build_overlay()
	_credits = CreditsView.new()
	add_child(_credits)
	_credits.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mp = MultiplayerUi.new()
	add_child(_mp)
	_mp.setup(_dictionary, _generator)
	_mp.round_begins.connect(_on_mp_round_begins)
	_mp.scoreboard_updated.connect(_on_mp_scoreboard)
	_mp.left_multiplayer.connect(_on_mp_left)
	_update_labels()


func _build_overlay() -> void:
	_overlay = Control.new()
	add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	_overlay.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(580, 0)
	_panels.append(panel)
	center.add_child(panel)

	var inner := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 32)
	panel.add_child(inner)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	inner.add_child(box)

	_overlay_title = Label.new()
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_title.custom_minimum_size = Vector2(500, 0)
	_overlay_title.add_theme_font_size_override("font_size", 60)
	_text_labels.append(_overlay_title)
	box.add_child(_overlay_title)

	_overlay_body = Label.new()
	_overlay_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_body.custom_minimum_size = Vector2(500, 0)
	_overlay_body.add_theme_font_size_override("font_size", 32)
	_text_labels.append(_overlay_body)
	box.add_child(_overlay_body)

	_play_button = _make_button("Jugar", 42)
	_play_button.custom_minimum_size = Vector2(0, 96)
	_play_button.pressed.connect(_on_play_pressed)
	box.add_child(_play_button)

	_mp_button = _make_button("Multijugador", 34)
	_mp_button.custom_minimum_size = Vector2(0, 84)
	_mp_button.pressed.connect(_on_multiplayer_pressed)
	box.add_child(_mp_button)

	_overlay_skin_button = _make_button("Estilo", 28)
	_overlay_skin_button.custom_minimum_size = Vector2(0, 72)
	_overlay_skin_button.pressed.connect(GameSettings.cycle_skin)
	box.add_child(_overlay_skin_button)

	_toggle_row = HBoxContainer.new()
	_toggle_row.add_theme_constant_override("separation", 14)
	box.add_child(_toggle_row)
	_sound_button = _make_button("", 26)
	_sound_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sound_button.custom_minimum_size = Vector2(0, 72)
	_sound_button.pressed.connect(_on_sound_toggled)
	_toggle_row.add_child(_sound_button)
	_haptics_button = _make_button("", 26)
	_haptics_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_haptics_button.custom_minimum_size = Vector2(0, 72)
	_haptics_button.pressed.connect(_on_haptics_toggled)
	_toggle_row.add_child(_haptics_button)
	_refresh_toggle_texts()

	_credits_button = _make_button("Créditos y licencias", 24)
	_credits_button.custom_minimum_size = Vector2(0, 64)
	_credits_button.pressed.connect(func() -> void: _credits.show_credits())
	box.add_child(_credits_button)


func _add_stat(parent: Control, caption: String) -> Label:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var caption_label := Label.new()
	caption_label.text = caption
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption_label.add_theme_font_size_override("font_size", 20)
	var value_label := Label.new()
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 44)
	box.add_child(caption_label)
	box.add_child(value_label)
	panel.add_child(box)
	parent.add_child(panel)
	_panels.append(panel)
	_dim_labels.append(caption_label)
	_text_labels.append(value_label)
	return value_label


func _make_button(text: String, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", font_size)
	button.pressed.connect(Feedback.click)
	_buttons.append(button)
	return button


func _safe_top_inset() -> float:
	var window := DisplayServer.window_get_size()
	if window.y <= 0:
		return 0.0
	var safe := DisplayServer.get_display_safe_area()
	return maxf(0.0, safe.position.y * get_viewport_rect().size.y / window.y)


# --- Skinning ----------------------------------------------------------------

func _current_skin() -> GameSkin:
	return GameSettings.current_skin()


func _apply_skin(skin: GameSkin) -> void:
	_background.set_skin(skin)
	_board_view.set_skin(skin)
	for panel in _panels:
		panel.add_theme_stylebox_override("panel", _panel_style(skin))
	for label in _text_labels:
		label.add_theme_color_override("font_color", skin.text_color)
	for label in _dim_labels:
		label.add_theme_color_override("font_color", skin.text_dim_color)
	for button in _buttons:
		_style_button(button, skin)
	_overlay_skin_button.text = "Estilo: " + skin.display_name
	_credits.set_skin(skin)
	_mp.apply_skin(skin)
	_scoreboard.apply_skin(skin)
	_rebuild_found_chips()
	_update_timer()


func _panel_style(skin: GameSkin) -> StyleBoxFlat:
	return UiStyle.panel(skin)


func _style_button(button: Button, skin: GameSkin) -> void:
	UiStyle.style_button(button, skin)


func _chip_style(skin: GameSkin) -> StyleBoxFlat:
	return UiStyle.chip(skin)


func _rebuild_found_chips() -> void:
	for child in _found_flow.get_children():
		child.queue_free()
	for i in range(_found.size() - 1, -1, -1):  # newest first
		_add_chip(_found[i], false)


func _add_chip(word: String, at_front: bool) -> void:
	var skin := _current_skin()
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_PASS  # let drags scroll the word list
	chip.add_theme_stylebox_override("panel", _chip_style(skin))
	var label := Label.new()
	label.text = word.to_upper()
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", skin.text_color)
	chip.add_child(label)
	_found_flow.add_child(chip)
	if at_front:
		_found_flow.move_child(chip, 0)


# --- Round flow ---------------------------------------------------------------

func _on_play_pressed() -> void:
	match _state:
		State.READY, State.FINISHED:
			_start_round()
		State.PAUSED:
			_resume_round()


## Stops the clock and covers the letters so nobody can study the board for free.
func _pause_round() -> void:
	if _state != State.PLAYING:
		return
	_state = State.PAUSED
	_board_view.active = false
	_board_view.revealed = false
	_show_overlay("Pausa", "El tiempo está detenido.", "Continuar", true)


func _resume_round() -> void:
	_state = State.PLAYING
	_board_view.revealed = true
	_board_view.active = true
	_overlay.visible = false


func _start_round() -> void:
	_set_mode(Mode.SOLO)
	var started := Time.get_ticks_msec()
	var board := _generator.generate_playable(_dictionary, MIN_PLAYABLE_WORDS)
	if OS.is_debug_build():
		board = _debug_board_override(board)
	_solutions = BoardSolver.solve(board, _dictionary)
	if OS.is_debug_build():
		print("DEBUG round_start_ms=%d" % (Time.get_ticks_msec() - started))
	_found.clear()
	_score = 0
	_record_at_start = GameSettings.high_score
	_time_left = ROUND_SECONDS
	_last_second = ceili(ROUND_SECONDS)
	_message_left = 0.0
	_set_word_text("", _current_skin().text_color)
	_board_view.set_board(board)
	_board_view.revealed = true
	_board_view.active = true
	_rebuild_found_chips()
	_update_labels()
	_update_timer()
	_overlay.visible = false
	_state = State.PLAYING
	if OS.is_debug_build():
		_print_debug_hints(board)


func _finish_round() -> void:
	_state = State.FINISHED
	_board_view.active = false
	if _mode == Mode.MULTI:
		# The host decides the final scores (shared words cancel): its results screen
		# opens by itself in a moment, on top of this one.
		_update_labels()
		_show_overlay("¡Tiempo!", "Calculando resultados…", "", false)
		return
	GameSettings.submit_score(_score)
	var is_record := _score > _record_at_start
	var longest := ""
	for word: String in _solutions:
		if word.length() > longest.length():
			longest = word
	var body := "Puntos: %d\nPalabras: %d de %d\nMás larga posible: %s" % [
		_score, _found.size(), _solutions.size(), longest.to_upper()]
	if is_record:
		body += "\n¡Nuevo récord!"
	Feedback.round_end(is_record)
	_update_labels()
	_show_overlay("¡Tiempo!", body, "Jugar de nuevo", true)


func _on_path_changed(word: String) -> void:
	_message_left = 0.0
	_set_word_text(_display_word(word), _current_skin().text_color)


func _on_word_submitted(word: String, path: Array) -> void:
	if _state != State.PLAYING or path.size() < 2:
		return
	var skin := _current_skin()
	if word.length() < BoardSolver.MIN_WORD_LENGTH:
		_reject(path, BoardView.Flash.INVALID, "Muy corta", skin.danger_color)
		Feedback.word_bad()
	elif word in _found:
		_reject(path, BoardView.Flash.REPEAT, "Repetida", skin.text_dim_color)
		Feedback.word_repeat()
	elif _dictionary.has_word(word):
		Feedback.word_ok(word.length())
		var points := _points_for(word.length())
		_score += points
		if _mode == Mode.MULTI:
			_mp.submit_word(word)  # the host has the final say; its scoreboard corrects this score
		else:
			GameSettings.submit_score(_score)  # saved right away: the record survives closing the app
		_found.append(word)
		_add_chip(word, true)
		_board_view.flash(path, BoardView.Flash.OK)
		_show_message("+%d" % points, skin.accent_color)
		_update_labels()
	else:
		_reject(path, BoardView.Flash.INVALID, "No existe", skin.danger_color)
		Feedback.word_bad()


func _reject(path: Array, kind: BoardView.Flash, text: String, color: Color) -> void:
	_board_view.flash(path, kind)
	_show_message(text, color)


func _points_for(length: int) -> int:
	return WordScoring.points_for(length)


func _show_message(text: String, color: Color) -> void:
	_set_word_text(text, color)
	_message_left = MESSAGE_SECONDS


func _set_word_text(text: String, color: Color) -> void:
	_word_label.text = text
	_word_label.add_theme_color_override("font_color", color)


func _display_word(word: String) -> String:
	return word.to_upper()


func _update_labels() -> void:
	_score_label.text = str(_score)
	_record_label.text = _rank_text() if _mode == Mode.MULTI else str(maxi(GameSettings.high_score, _score))
	_found_caption.text = "PALABRAS ENCONTRADAS (%d)" % _found.size()


## "2/4": this player's place among the provisional scores of the room.
func _rank_text() -> String:
	if _mp_scores.is_empty():
		return "-"
	var ahead := 0
	for entry: Dictionary in _mp_scores:
		if entry["score"] > _score:
			ahead += 1
	return "%d/%d" % [ahead + 1, _mp_scores.size()]


func _update_timer() -> void:
	var seconds := ceili(_time_left)
	_timer_label.text = "%d:%02d" % [seconds / 60, seconds % 60]
	var low := _state == State.PLAYING and _time_left <= LOW_TIME_SECONDS
	var skin := _current_skin()
	_timer_label.add_theme_color_override("font_color", skin.danger_color if low else skin.text_color)


func _on_sound_toggled() -> void:
	GameSettings.set_sound_enabled(not GameSettings.sound_enabled)
	_refresh_toggle_texts()


func _on_haptics_toggled() -> void:
	GameSettings.set_haptics_enabled(not GameSettings.haptics_enabled)
	_refresh_toggle_texts()


func _refresh_toggle_texts() -> void:
	_sound_button.text = "Sonido: %s" % ("Sí" if GameSettings.sound_enabled else "No")
	_haptics_button.text = "Vibración: %s" % ("Sí" if GameSettings.haptics_enabled else "No")


func _show_overlay(title: String, body: String, button_text: String, show_buttons: bool) -> void:
	_overlay_title.text = title
	_overlay_body.text = body
	_play_button.text = button_text
	_play_button.visible = show_buttons
	_mp_button.visible = show_buttons
	_overlay_skin_button.visible = show_buttons
	_toggle_row.visible = show_buttons
	_credits_button.visible = show_buttons
	_overlay.visible = true


# --- Multiplayer ---------------------------------------------------------------

func _on_multiplayer_pressed() -> void:
	if _state != State.READY and _state != State.FINISHED:
		return
	_overlay.visible = false
	_mp.open()


func _set_mode(mode: Mode) -> void:
	_mode = mode
	var in_room := mode == Mode.MULTI
	_scoreboard.visible = in_room
	_record_caption.text = "PUESTO" if in_room else "RÉCORD"
	_mp_scores = []
	_scoreboard.set_board([], _mp.my_id())


## A round of the room starts here: same board for everybody, a short countdown, then
## the clock. The letters stay hidden until the countdown ends, so nobody gets a head start.
func _on_mp_round_begins(board: PackedStringArray, countdown: float, duration: float) -> void:
	_set_mode(Mode.MULTI)
	_found.clear()
	_score = 0
	_time_left = duration
	_countdown_left = countdown
	_last_second = ceili(countdown) + 1
	_message_left = 0.0
	_board_view.set_board(board)
	_board_view.revealed = false
	_board_view.active = false
	_rebuild_found_chips()
	_update_labels()
	_update_timer()
	_overlay.visible = false
	_state = State.COUNTDOWN


func _run_countdown(delta: float) -> void:
	_countdown_left -= minf(delta, MAX_TIME_STEP)
	var shown := ceili(_countdown_left)
	if shown != _last_second:
		_last_second = shown
		if shown > 0:
			Feedback.tick()
			_set_word_text(str(shown), _current_skin().accent_color)
	if _countdown_left <= 0.0:
		_state = State.PLAYING
		_last_second = ceili(_time_left)
		_board_view.revealed = true
		_board_view.active = true
		_show_message("¡Ya!", _current_skin().accent_color)


## Provisional scores of the whole room. The host's number for this player replaces
## the one counted locally, so both always agree.
func _on_mp_scoreboard(board: Array, my_id: int) -> void:
	_mp_scores = board
	for entry: Dictionary in board:
		if entry["id"] == my_id:
			_score = entry["score"]
	_scoreboard.set_board(board, my_id)
	_update_labels()


func _on_mp_left() -> void:
	_set_mode(Mode.SOLO)
	_state = State.READY
	_board_view.active = false
	_board_view.revealed = false
	_time_left = ROUND_SECONDS
	_score = 0
	_found.clear()
	_rebuild_found_chips()
	_update_labels()
	_update_timer()
	_set_word_text("", _current_skin().text_color)
	_show_overlay(GAME_TITLE, INTRO_TEXT, "Jugar", true)


# --- Debug -----------------------------------------------------------------

## Debug builds only: user://debug_board.txt holds 16 comma-separated tiles that
## replace the random board (used to take reproducible store screenshots).
func _debug_board_override(fallback: PackedStringArray) -> PackedStringArray:
	var path := "user://debug_board.txt"
	if not FileAccess.file_exists(path):
		return fallback
	var tiles := FileAccess.get_file_as_string(path).strip_edges().split(",")
	return tiles if tiles.size() == BoardView.SIZE * BoardView.SIZE else fallback


## Prints geometry and a few solvable words so UI tests on a device/emulator
## can drive the board without guessing.
func _print_debug_hints(board: PackedStringArray) -> void:
	print("DEBUG board=%s" % ",".join(board))
	print("DEBUG viewport=%s window=%s" % [get_viewport_rect().size, DisplayServer.window_get_size()])
	var rect := _board_view.get_global_rect()
	print("DEBUG board_rect=%s" % rect)
	var shown := 0
	for word: String in _solutions:
		if word.length() >= 5 and shown < 3:
			print("DEBUG word=%s path=%s" % [word, _solutions[word]])
			shown += 1
