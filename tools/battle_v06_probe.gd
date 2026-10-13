extends "res://scripts/world_map.gd"

# Observe production input routing. The battle model, navigation, GUI and
# renderer remain the same classes used by the exported Android game.
var map_tap_count := 0
var menu_open_count := 0

func _handle_map_tap(point: Vector2) -> void:
    map_tap_count += 1
    super._handle_map_tap(point)

func _open_menu() -> void:
    menu_open_count += 1
