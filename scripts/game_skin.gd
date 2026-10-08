class_name GameSkin
extends Resource
## Visual theme for the whole game. Scenes read every color, shape and effect
## from here, so a new look only needs a new .tres file in res://skins/.

enum Background { WOOD_GRAIN, GRADIENT_BUBBLES, DARK_GRID }

@export var display_name := "Skin"

@export_group("Background")
@export var background_kind: Background = Background.WOOD_GRAIN
@export var bg_color_a := Color.BLACK
@export var bg_color_b := Color.BLACK
## Plank seams (wood), bubbles (gradient) or grid lines (dark).
@export var bg_accent := Color.WHITE

@export_group("Text")
@export var text_color := Color.WHITE
@export var text_dim_color := Color.GRAY
@export var accent_color := Color.YELLOW
@export var danger_color := Color.RED

@export_group("Panels")
@export var panel_color := Color(0, 0, 0, 0.5)
@export var panel_border_color := Color.WHITE
@export var panel_border_width := 2
@export var panel_radius := 16

@export_group("Buttons")
@export var button_color := Color.WHITE
@export var button_text_color := Color.BLACK
@export var button_border_color := Color.TRANSPARENT
@export var button_border_width := 0
@export var button_radius := 16

@export_group("Board")
@export var board_color := Color.BLACK
@export var board_border_color := Color.WHITE
@export var board_radius := 24
@export var path_color := Color(1, 1, 1, 0.6)

@export_group("Tiles")
@export var tile_color := Color.WHITE
@export var tile_border_color := Color.GRAY
@export var tile_text_color := Color.BLACK
@export var tile_selected_color := Color.YELLOW
@export var tile_selected_text_color := Color.BLACK
@export var tile_valid_color := Color.GREEN
@export var tile_invalid_color := Color.RED
@export var tile_repeat_color := Color.GRAY
## Corner radius as a fraction of the tile size (0.5 = circle).
@export_range(0.0, 0.5) var tile_radius := 0.16
@export var tile_border_width := 3
## Space between tiles as a fraction of the cell size.
@export_range(0.0, 0.4) var tile_gap := 0.1
@export var tile_shadow_color := Color(0, 0, 0, 0.4)
@export var tile_shadow_size := 8
@export var tile_shadow_offset := Vector2(0, 5)
## Max random rotation per tile, in degrees (dice feel).
@export var tile_tilt_degrees := 0.0
