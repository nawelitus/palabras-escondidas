class_name MpPanel
extends Control
## Base of every multiplayer screen: a dimmed full-screen overlay with a skinned panel.
## A compact panel is centered and as tall as its content; a tall one fills the screen,
## scrolls its body and keeps the footer buttons always visible. Subclasses add their
## widgets to `body` and `footer`, and redraw dynamic content in `_render()`.

const SIDE_MARGIN := 24
const TOP_MARGIN := 72
const BOTTOM_MARGIN := 24

var title_label: Label
var body := VBoxContainer.new()
var footer := VBoxContainer.new()

var _compact: bool
var _skin: GameSkin
var _panel := PanelContainer.new()
var _buttons: Array[Button] = []
var _labels: Array[Label] = []
var _dim_labels: Array[Label] = []
var _edits: Array[LineEdit] = []


func _init(title: String, compact: bool = false) -> void:
	_compact = compact
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.88)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var holder: Container
	if compact:
		holder = CenterContainer.new()
		_panel.custom_minimum_size = Vector2(600, 0)
	else:
		holder = MarginContainer.new()
		holder.add_theme_constant_override("margin_left", SIDE_MARGIN)
		holder.add_theme_constant_override("margin_right", SIDE_MARGIN)
		holder.add_theme_constant_override("margin_top", TOP_MARGIN)
		holder.add_theme_constant_override("margin_bottom", BOTTOM_MARGIN)
	add_child(holder)
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(_panel)

	var inner := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 26)
	_panel.add_child(inner)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	inner.add_child(column)

	title_label = make_label(title, 46, false)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title_label)

	body.add_theme_constant_override("separation", 12)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if compact:
		column.add_child(body)
	else:
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		column.add_child(scroll)
		scroll.add_child(body)
	footer.add_theme_constant_override("separation", 12)
	column.add_child(footer)


func show_panel() -> void:
	_render()
	visible = true


func hide_panel() -> void:
	visible = false


func apply_skin(skin: GameSkin) -> void:
	_skin = skin
	_panel.add_theme_stylebox_override("panel", UiStyle.panel(skin) if _compact else UiStyle.solid_panel(skin))
	for label in _labels:
		label.add_theme_color_override("font_color", skin.text_color)
	for label in _dim_labels:
		label.add_theme_color_override("font_color", skin.text_dim_color)
	for button in _buttons:
		UiStyle.style_button(button, skin)
	for edit in _edits:
		UiStyle.style_line_edit(edit, skin)
	_render()


## Override to rebuild the dynamic widgets from the data the screen holds.
func _render() -> void:
	pass


func current_skin() -> GameSkin:
	return _skin if _skin != null else GameSettings.current_skin()


## A button registered for skinning; the caller places it in `body` or `footer`.
func make_button(text: String, font_size: int = 30, min_height: int = 80) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, min_height)
	button.add_theme_font_size_override("font_size", font_size)
	button.pressed.connect(Feedback.click)
	_buttons.append(button)
	if _skin != null:
		UiStyle.style_button(button, _skin)
	return button


## A button for rows of a rebuilt list: styled now, but not kept in the registry, so
## discarding the list does not leave dead buttons behind.
func make_dynamic_button(text: String, font_size: int = 28, min_height: int = 76) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, min_height)
	button.add_theme_font_size_override("font_size", font_size)
	button.pressed.connect(Feedback.click)
	UiStyle.style_button(button, current_skin())
	return button


## A label registered for skinning (dim = the quieter text color).
func make_label(text: String, font_size: int = 26, dim: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	if dim:
		_dim_labels.append(label)
	else:
		_labels.append(label)
	var skin := current_skin()
	label.add_theme_color_override("font_color", skin.text_dim_color if dim else skin.text_color)
	return label


## A label for content that is rebuilt (rosters, rankings): styled now, never registered.
func make_dynamic_label(text: String, font_size: int = 26, dim: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	var skin := current_skin()
	label.add_theme_color_override("font_color", skin.text_dim_color if dim else skin.text_color)
	return label


func make_line_edit(placeholder: String, max_chars: int, font_size: int = 32) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.max_length = max_chars
	edit.custom_minimum_size = Vector2(0, 72)
	edit.add_theme_font_size_override("font_size", font_size)
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.text_submitted.connect(func(_text: String) -> void:
		edit.release_focus()
		DisplayServer.virtual_keyboard_hide())
	_edits.append(edit)
	UiStyle.style_line_edit(edit, current_skin())
	return edit


## Removes and frees every child of a container (before rebuilding a list).
static func clear_children(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


## A skinned row for lists: a panel with the text inside. Not registered: lists are
## rebuilt by _render() whenever the data or the skin changes.
func make_row(text: String, highlighted: bool = false, dim: bool = false, font_size: int = 28) -> PanelContainer:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS  # drags still scroll the list
	row.add_theme_stylebox_override("panel", UiStyle.row(current_skin(), highlighted))
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var skin := current_skin()
	label.add_theme_color_override("font_color", skin.text_dim_color if dim else skin.text_color)
	row.add_child(label)
	return row
