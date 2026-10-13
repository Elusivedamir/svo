extends "res://scripts/world_map.gd"

# Test-only observation: retain real pathfinding and count issued move orders.
var move_order_count: int = 0
var menu_open_count: int = 0

func _request_move(screen_point: Vector2) -> void:
    move_order_count += 1
    super._request_move(screen_point)

func _open_menu() -> void:
    menu_open_count += 1
