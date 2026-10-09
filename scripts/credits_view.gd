class_name CreditsView
extends Control
## Full-screen credits and open-source licenses. The long text is built the first
## time the screen is opened, so it costs nothing at startup.

signal closed

const APP_VERSION := "1.1.0"
const REPO_URL := "https://github.com/nawelitus/palabras-escondidas"
const TOP_MARGIN := 72
const SIDE_MARGIN := 24

var _panel: PanelContainer
var _title: Label
var _body: RichTextLabel
var _scroll: ScrollContainer
var _back_button: Button
var _text_built := false
var _building := false
var _opened_at := 0


func _init() -> void:
	visible = false
	_build()


func set_skin(skin: GameSkin) -> void:
	_panel.add_theme_stylebox_override("panel", UiStyle.solid_panel(skin))
	_title.add_theme_color_override("font_color", skin.text_color)
	_body.add_theme_color_override("default_color", skin.text_color)
	UiStyle.style_button(_back_button, skin)


func show_credits() -> void:
	_scroll.scroll_vertical = 0
	visible = true
	if _text_built or _building:
		return
	# Show the screen right away and fill the long text after two frames, so the
	# tap feels instant even on slow phones.
	_building = true
	_body.text = "Cargando…"
	await get_tree().process_frame
	await get_tree().process_frame
	_opened_at = Time.get_ticks_msec()
	_body.text = _credits_text()
	_text_built = true
	_building = false


func _on_body_finished() -> void:
	if OS.is_debug_build() and _opened_at > 0:
		print("DEBUG credits_layout_ms=%d chars=%d" % [Time.get_ticks_msec() - _opened_at, _body.text.length()])
		_opened_at = 0


func hide_credits() -> void:
	visible = false
	closed.emit()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.95)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", SIDE_MARGIN)
	margin.add_theme_constant_override("margin_right", SIDE_MARGIN)
	margin.add_theme_constant_override("margin_top", TOP_MARGIN)
	margin.add_theme_constant_override("margin_bottom", SIDE_MARGIN)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel = PanelContainer.new()
	margin.add_child(_panel)
	var inner := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 24)
	_panel.add_child(inner)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	inner.add_child(column)

	_title = Label.new()
	_title.text = "Créditos y licencias"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 44)
	column.add_child(_title)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = false
	_body.fit_content = true
	_body.scroll_active = false
	_body.threaded = true  # lay out the long text in a background thread
	_body.finished.connect(_on_body_finished)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# PASS lets touch drags reach the ScrollContainer; STOP would swallow them.
	_body.mouse_filter = Control.MOUSE_FILTER_PASS
	_body.add_theme_font_size_override("normal_font_size", 22)
	_scroll.add_child(_body)

	_back_button = Button.new()
	_back_button.text = "Volver"
	_back_button.focus_mode = Control.FOCUS_NONE
	_back_button.custom_minimum_size = Vector2(0, 84)
	_back_button.add_theme_font_size_override("font_size", 34)
	_back_button.pressed.connect(Feedback.click)
	_back_button.pressed.connect(hide_credits)
	column.add_child(_back_button)


func _credits_text() -> String:
	var text := "Palabras Escondidas\nVersión %s\n\n" % APP_VERSION
	text += "Hecho por Nahuel\nDe Lavalle para el Mundo\n\n"
	text += "DICCIONARIO\n"
	text += "Las palabras provienen de los diccionarios Hunspell es_ES y es_AR del proyecto RLA-ES "
	text += "(Recursos Lingüísticos Abiertos del Español), con licencia MPL 1.1 "
	text += "(https://www.mozilla.org/MPL/1.1/). Para este juego se expandieron las formas, "
	text += "se quitaron las tildes y se descartaron nombres propios y siglas. "
	text += "La lista modificada y el programa que la genera están disponibles en:\n%s\n\n" % REPO_URL
	text += "MOTOR Y FUENTE\n"
	text += "Hecho con Godot Engine (https://godotengine.org). "
	text += "El texto usa la fuente Open Sans, con licencia SIL Open Font License 1.1.\n\n"
	text += "LICENCIA DE GODOT ENGINE\n%s\n\n" % _reflow(Engine.get_license_text().strip_edges())
	text += "COMPONENTES DE TERCEROS DE GODOT\n%s\n\n" % _components_text()
	text += "TEXTOS DE LAS LICENCIAS\n%s\n" % _licenses_text()
	return text


## Joins hard-wrapped lines into paragraphs; blank lines still separate paragraphs.
func _reflow(text: String) -> String:
	var marker := "\u0001"
	return text.replace("\n\n", marker).replace("\n", " ").replace(marker, "\n\n")


func _components_text() -> String:
	var lines := PackedStringArray()
	for component: Dictionary in Engine.get_copyright_info():
		lines.append("• %s" % component["name"])
		for part: Dictionary in component["parts"]:
			for line in part["copyright"]:
				lines.append("    %s" % line)
			lines.append("    Licencia: %s" % part["license"])
	return "\n".join(lines)


func _licenses_text() -> String:
	var info := Engine.get_license_info()
	var chunks := PackedStringArray()
	for license_name: String in info:
		chunks.append("--- %s ---\n%s" % [license_name, String(info[license_name]).strip_edges()])
	return "\n\n".join(chunks)
