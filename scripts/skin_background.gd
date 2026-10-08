class_name SkinBackground
extends Control
## Full-screen background drawn from the active GameSkin.

const BUBBLE_COUNT := 16

var _skin: GameSkin
var _grain: NoiseTexture2D
var _gradient: GradientTexture2D
var _bubbles: Array[Dictionary] = []
var _time := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_skin(skin: GameSkin) -> void:
	_skin = skin
	_build_textures()
	set_process(skin.background_kind == GameSkin.Background.GRADIENT_BUBBLES)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	for bubble in _bubbles:
		bubble["y"] = fposmod(bubble["y"] - bubble["speed"] * delta, 1.0)
	queue_redraw()


func _draw() -> void:
	if _skin == null:
		return
	match _skin.background_kind:
		GameSkin.Background.WOOD_GRAIN:
			_draw_wood()
		GameSkin.Background.GRADIENT_BUBBLES:
			_draw_bubbles()
		GameSkin.Background.DARK_GRID:
			_draw_dark_grid()


func _build_textures() -> void:
	_grain = null
	_gradient = null
	_bubbles.clear()
	match _skin.background_kind:
		GameSkin.Background.WOOD_GRAIN:
			# A short, wide noise texture stretched to the screen turns into long
			# vertical streaks, which reads as wood grain.
			var noise := FastNoiseLite.new()
			noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			noise.frequency = 0.1
			noise.fractal_octaves = 3
			_grain = NoiseTexture2D.new()
			_grain.width = 360
			_grain.height = 24
			_grain.noise = noise
			_grain.color_ramp = _two_color_ramp(_skin.bg_color_a, _skin.bg_color_b)
			_grain.changed.connect(queue_redraw)
		GameSkin.Background.GRADIENT_BUBBLES:
			_gradient = GradientTexture2D.new()
			_gradient.gradient = _two_color_ramp(_skin.bg_color_a, _skin.bg_color_b)
			_gradient.fill_from = Vector2(0.0, 0.0)
			_gradient.fill_to = Vector2(0.0, 1.0)
			_gradient.width = 4
			_gradient.height = 256
			_seed_bubbles()


func _two_color_ramp(from: Color, to: Color) -> Gradient:
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 1.0])
	ramp.colors = PackedColorArray([from, to])
	return ramp


func _seed_bubbles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in BUBBLE_COUNT:
		_bubbles.append({
			"x": rng.randf(),
			"y": rng.randf(),
			"r": rng.randf_range(14.0, 60.0),
			"speed": rng.randf_range(0.01, 0.04),
			"phase": rng.randf() * TAU,
		})


func _draw_wood() -> void:
	var area := Rect2(Vector2.ZERO, size)
	draw_rect(area, _skin.bg_color_b)
	if _grain != null:
		draw_texture_rect(_grain, area, false)
	var plank := size.x / 4.0
	for i in range(1, 4):
		var x := plank * i
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(_skin.bg_accent, 0.7), 4.0)
		draw_line(Vector2(x + 3, 0), Vector2(x + 3, size.y), Color(1, 1, 1, 0.06), 2.0)


func _draw_bubbles() -> void:
	if _gradient != null:
		draw_texture_rect(_gradient, Rect2(Vector2.ZERO, size), false)
	for bubble in _bubbles:
		var pos := Vector2(
			bubble["x"] * size.x + sin(_time + bubble["phase"]) * 12.0,
			bubble["y"] * size.y)
		draw_circle(pos, bubble["r"], Color(_skin.bg_accent, 0.12))
		draw_arc(pos, bubble["r"], 0.0, TAU, 32, Color(_skin.bg_accent, 0.25), 2.0, true)


func _draw_dark_grid() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _skin.bg_color_a)
	var center := size * Vector2(0.5, 0.4)
	for i in 5:
		draw_circle(center, size.x * (0.9 - i * 0.15), Color(_skin.bg_color_b, 0.35))
	var line_color := Color(_skin.bg_accent, 0.06)
	var step := 80.0
	var x := 0.0
	while x <= size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), line_color, 2.0)
		x += step
	var y := 0.0
	while y <= size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), line_color, 2.0)
		y += step
