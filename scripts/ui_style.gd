class_name UiStyle
extends RefCounted
## Skin-driven styles shared by every screen, so panels, buttons and list rows look
## the same everywhere and a new skin only has to describe colors once.


static func panel(skin: GameSkin) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = skin.panel_color
	style.border_color = skin.panel_border_color
	style.set_border_width_all(skin.panel_border_width)
	style.set_corner_radius_all(skin.panel_radius)
	style.set_content_margin_all(10)
	style.anti_aliasing = true
	return style


## Opaque panel for full-height screens, so what is behind never shows through the text.
## It is the skin's own (often translucent) panel color laid over a darkened version of
## the skin's background, so a skin with a see-through panel keeps its look instead of
## turning flat gray.
static func solid_panel(skin: GameSkin) -> StyleBoxFlat:
	var style := panel(skin)
	var base := skin.bg_color_a.darkened(0.55)
	var blended := base.lerp(Color(skin.panel_color, 1.0), skin.panel_color.a)
	style.bg_color = Color(blended, 1.0)
	return style


static func chip(skin: GameSkin) -> StyleBoxFlat:
	var style := panel(skin)
	style.set_corner_radius_all(maxi(skin.panel_radius / 2, 8))
	style.set_content_margin_all(8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	return style


## One row of a list (a player, a room). The highlighted one marks "you" or the selection.
static func row(skin: GameSkin, highlighted: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(skin.accent_color, 0.28) if highlighted else Color(skin.text_color, 0.07)
	style.border_color = skin.accent_color if highlighted else Color(skin.text_color, 0.12)
	style.set_border_width_all(2 if highlighted else 1)
	style.set_corner_radius_all(maxi(skin.panel_radius / 2, 8))
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.anti_aliasing = true
	return style


static func style_button(button: Button, skin: GameSkin) -> void:
	var fills := {
		"normal": skin.button_color,
		"hover": skin.button_color.lightened(0.12),
		"pressed": skin.button_color.darkened(0.15),
		"focus": skin.button_color,
		"disabled": skin.button_color.darkened(0.45),
	}
	for state: String in fills:
		var style := StyleBoxFlat.new()
		style.bg_color = fills[state]
		style.border_color = skin.button_border_color
		style.set_border_width_all(skin.button_border_width)
		style.set_corner_radius_all(skin.button_radius)
		style.content_margin_left = 22
		style.content_margin_right = 22
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		style.anti_aliasing = true
		button.add_theme_stylebox_override(state, style)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, skin.button_text_color)
	button.add_theme_color_override("font_disabled_color", Color(skin.button_text_color, 0.45))


static func style_line_edit(edit: LineEdit, skin: GameSkin) -> void:
	for state in ["normal", "focus", "read_only"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(skin.text_color, 0.1)
		style.border_color = skin.accent_color if state == "focus" else Color(skin.text_color, 0.35)
		style.set_border_width_all(2)
		style.set_corner_radius_all(maxi(skin.panel_radius / 2, 8))
		style.content_margin_left = 16
		style.content_margin_right = 16
		style.content_margin_top = 12
		style.content_margin_bottom = 12
		style.anti_aliasing = true
		edit.add_theme_stylebox_override(state, style)
	edit.add_theme_color_override("font_color", skin.text_color)
	edit.add_theme_color_override("font_placeholder_color", skin.text_dim_color)
	edit.add_theme_color_override("caret_color", skin.accent_color)
