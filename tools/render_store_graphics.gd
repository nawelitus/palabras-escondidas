extends SceneTree
## Renders the Google Play graphics with the game's own classes and font:
##   store/assets/icon_512.png      (512x512, from icon.svg)
##   store/assets/feature_1024x500.png (24-bit, no alpha)
## It needs a real window (not --headless):
##   godot --path . --resolution 1024x500 --rendering-driver opengl3 --quit-after 900 -s tools/render_store_graphics.gd

const OUT_DIR := "res://store/assets"
## Snake path that spells ESCONDIDAS on the showcase board below.
const SHOWCASE_BOARD := ["e", "s", "c", "o", "d", "i", "d", "n", "a", "s", "t", "e", "l", "o", "r", "a"]
const SHOWCASE_PATH := [0, 1, 2, 3, 7, 6, 5, 4, 8, 9]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_render_icon()
	await _render_feature_graphic()
	quit()


func _render_icon() -> void:
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	var image := Image.new()
	var err := image.load_svg_from_string(svg, 1.0)
	print("icon: err=%d size=%s" % [err, image.get_size()])
	image.save_png(OUT_DIR + "/icon_512.png")


func _render_feature_graphic() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED  # use real pixels
	var skin := load("res://skins/wood.tres") as GameSkin

	var background := SkinBackground.new()
	root.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.set_skin(skin)

	var board := BoardView.new()
	root.add_child(board)
	board.position = Vector2(548, 30)
	board.size = Vector2(440, 440)
	board.set_skin(skin)
	board.set_board(PackedStringArray(SHOWCASE_BOARD))
	board.revealed = true
	board._path.assign(SHOWCASE_PATH)
	board.queue_redraw()

	# Soft dark gradient behind the text so it stays readable over the wood grain.
	var fade := GradientTexture2D.new()
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 1.0])
	ramp.colors = PackedColorArray([Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.0)])
	fade.gradient = ramp
	fade.fill_from = Vector2(0.0, 0.0)
	fade.fill_to = Vector2(1.0, 0.0)
	fade.width = 256
	fade.height = 4
	var fade_rect := TextureRect.new()
	fade_rect.texture = fade
	fade_rect.stretch_mode = TextureRect.STRETCH_SCALE
	fade_rect.position = Vector2.ZERO
	fade_rect.size = Vector2(560, 500)
	root.add_child(fade_rect)

	var title := Label.new()
	title.text = "Palabras\nEscondidas"
	title.position = Vector2(48, 58)
	title.add_theme_font_size_override("font_size", 78)
	title.add_theme_color_override("font_color", skin.text_color)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 5)
	title.add_theme_constant_override("line_spacing", -6)
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Une letras vecinas y encuentra las palabras antes de que acabe el tiempo."
	subtitle.position = Vector2(52, 262)
	subtitle.custom_minimum_size = Vector2(470, 0)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 28)
	subtitle.add_theme_color_override("font_color", skin.text_color)
	subtitle.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	subtitle.add_theme_constant_override("shadow_offset_y", 3)
	root.add_child(subtitle)

	var tags := Label.new()
	tags.text = "Sin anuncios  ·  Sin internet  ·  3 estilos"
	tags.position = Vector2(52, 410)
	tags.add_theme_font_size_override("font_size", 24)
	tags.add_theme_color_override("font_color", skin.accent_color)
	root.add_child(tags)

	# The wood grain texture is generated in a thread: wait until it is ready.
	for _i in 90:
		await process_frame
	await create_timer(1.0).timeout
	for _i in 5:
		await process_frame

	var image := root.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	print("feature: size=%s" % image.get_size())
	image.save_png(OUT_DIR + "/feature_1024x500.png")
