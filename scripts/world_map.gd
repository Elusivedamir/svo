extends Node2D

# Stage 3: real, separate map scene, intentionally no tactical objects or HUD.
# Scene contents stay separated from menu/loading assets for future gameplay.
const TERRAIN: Texture2D = preload("res://assets/map/terrain_v0.3.png")
const MAP_METADATA: String = "res://data/map_v0.3.json"
const MENU: String = "res://scenes/main_menu.tscn"
const WORLD_SIZE: Vector2 = Vector2(6400, 3600)

var terrain: Sprite2D
var camera: Camera2D
var is_returning := false

func _ready() -> void:
    var map_file := FileAccess.open(MAP_METADATA, FileAccess.READ)
    if map_file == null:
        push_error("Map feature data not available: " + MAP_METADATA)
        return
    var parsed: Variant = JSON.parse_string(map_file.get_as_text())
    if not (parsed is Dictionary):
        push_error("Invalid map feature JSON")
        return

    terrain = Sprite2D.new()
    terrain.texture = TERRAIN
    terrain.centered = false
    terrain.scale = Vector2(2.0, 2.0)
    terrain.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    add_child(terrain)

    camera = Camera2D.new()
    camera.enabled = true
    camera.position = WORLD_SIZE * 0.5
    add_child(camera)
    get_viewport().size_changed.connect(_fit_camera)
    _fit_camera()
    print("SMOKE_MAP_READY")

func _fit_camera() -> void:
    if not is_instance_valid(camera):
        return
    var view: Vector2 = get_viewport_rect().size
    # Scale to cover the full landscape viewport, not stretch the world.
    var fit_zoom: float = maxf(view.x / WORLD_SIZE.x, view.y / WORLD_SIZE.y)
    camera.zoom = Vector2.ONE * maxf(fit_zoom, 0.01)

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_cancel"):
        _back_to_menu()
        get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_GO_BACK_REQUEST:
        _back_to_menu()

func _back_to_menu() -> void:
    if is_returning:
        return
    is_returning = true
    call_deferred("_open_menu")

func _open_menu() -> void:
    if is_inside_tree():
        get_tree().change_scene_to_file(MENU)
