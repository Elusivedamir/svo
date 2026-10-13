extends "res://scripts/world_map.gd"

# Observe the real production controller without replacing its pathfinding.
var move_order_count: int = 0
var menu_open_count: int = 0

func _init() -> void:
    legacy_regression_mode = true

func _request_move(screen_point: Vector2) -> void:
    move_order_count += 1
    super._request_move(screen_point)

func _open_menu() -> void:
    menu_open_count += 1
