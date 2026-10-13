extends Node2D

# v0.4: mobile camera controls over the verified v0.3.6 landscape.
# Tap to pathfind, swipe to pan, pinch to zoom; camera controls never issue orders.
const MAP_TEXTURE: Texture2D = preload("res://assets/map/terrain_v0.3.4.png")
const NAV_TEXTURE: Texture2D = preload("res://assets/map/navigation_v0.3.6.png")
const TERRAIN_CLARITY: Shader = preload("res://shaders/terrain_clarity.gdshader")
const MENU_SCENE := "res://scenes/main_menu.tscn"
const WORLD_SIZE := Vector2(12800.0, 7200.0)
const SECTOR_SIZE := Vector2(6400.0, 3600.0)
const EXPECTED_NAV_SIZE := Vector2i(418, 236)
const EXPECTED_TEXTURE_SIZE := Vector2i(3344, 1882)
const CELL_FIELD := 0
const CELL_ROAD := 1
const CELL_WOODS := 2
const CELL_HOUSE := 3
const CELL_WATER := 4
const CELL_BRIDGE := 5
const TAP_SLOP := 20.0
const MIN_PINCH_DISTANCE := 8.0

var terrain: Sprite2D
var camera: Camera2D
var nav: AStarGrid2D
var nav_types: PackedByteArray = PackedByteArray()
var nav_size: Vector2i
var nav_cell: Vector2
var ball_pos: Vector2
var path: PackedVector2Array = PackedVector2Array()
var path_next: int = 0
var blocked_at: Vector2 = Vector2.ZERO
var blocked_timer := 0.0
var returning := false
var camera_min_zoom := 0.25
var camera_max_zoom := 1.0
var camera_view_initialized := false
var camera_controls: CanvasLayer
var focus_button: Button
var touch_points: Dictionary = {}
var ui_touch_ids: Dictionary = {}
var gesture_was_multi := false
var single_touch_index := -1
var pinch_ids := Vector2i(-1, -1)
var pinch_distance := 0.0
var pinch_center := Vector2.ZERO
var touch_down := false
var touch_start := Vector2.ZERO
var touch_last := Vector2.ZERO
var touch_moved := false

func _ready() -> void:
    var img: Image = NAV_TEXTURE.get_image()
    if img == null or img.get_width() < 20 or img.get_height() < 20:
        push_error("Navigation grid not imported")
        return
    nav_size = Vector2i(img.get_width(), img.get_height())
    if nav_size != EXPECTED_NAV_SIZE or Vector2i(MAP_TEXTURE.get_size()) != EXPECTED_TEXTURE_SIZE:
        push_error("Map and navigation sizes do not match v0.3.6 water-safe unique world")
        return
    nav_cell = WORLD_SIZE / Vector2(nav_size)
    nav = AStarGrid2D.new()
    nav.region = Rect2i(Vector2i.ZERO, nav_size)
    nav.cell_size = nav_cell
    nav.offset = nav_cell * 0.5
    nav.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
    nav.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
    nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
    nav.update()
    nav_types.resize(nav_size.x * nav_size.y)
    var buildings := 0
    var water := 0
    var road := 0
    var wood := 0
    var bridges := 0
    for y in range(nav_size.y):
        for x in range(nav_size.x):
            var p: Color = img.get_pixel(x, y)
            var terrain_type: int = _classify_color(p)
            nav_types[y * nav_size.x + x] = terrain_type
            var id := Vector2i(x, y)
            match terrain_type:
                CELL_HOUSE:
                    nav.set_point_solid(id, true)
                    buildings += 1
                CELL_WATER:
                    nav.set_point_solid(id, true)
                    water += 1
                CELL_ROAD:
                    nav.set_point_weight_scale(id, 1.0)
                    road += 1
                CELL_WOODS:
                    nav.set_point_weight_scale(id, 2.7)
                    wood += 1
                CELL_BRIDGE:
                    nav.set_point_weight_scale(id, 1.1)
                    bridges += 1
                _:
                    nav.set_point_weight_scale(id, 1.6)

    terrain = Sprite2D.new()
    terrain.texture = MAP_TEXTURE
    terrain.centered = false
    terrain.z_index = -5
    terrain.scale = WORLD_SIZE / Vector2(MAP_TEXTURE.get_size())
    terrain.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    var clarity_material := ShaderMaterial.new()
    clarity_material.shader = TERRAIN_CLARITY
    terrain.material = clarity_material
    add_child(terrain)

    camera = Camera2D.new()
    camera.enabled = true
    # Open in the original home sector, rather than zooming out and shrinking every building.
    camera.position = SECTOR_SIZE * 0.5
    camera.position_smoothing_enabled = false
    add_child(camera)
    get_viewport().size_changed.connect(_resize_camera)
    _resize_camera()

    var spawn := Vector2i(100, 56)
    if nav.is_point_solid(spawn):
        push_error("Test marker spawn is blocked")
        return
    ball_pos = nav.get_point_position(spawn)
    _create_camera_controls()
    queue_redraw()
    print("SMOKE_MAP_READY")
    print("SMOKE_NAV_READY field/road/woods/houses/water/bridge: ", nav_size, "/", road, "/", wood, "/", buildings, "/", water, "/", bridges)
    if nav.is_point_solid(Vector2i(84, 93)) and nav.is_point_solid(Vector2i(350, 125)):
        print("SMOKE_NAV_OBSTACLES_BLOCKED")
    else:
        push_error("Navigation solid test failed")
    # Test the mapped bridge and obstacle independently from raster dimensions.
    if not nav.is_point_solid(Vector2i(60, 76)) and int(nav_types[76 * nav_size.x + 60]) == CELL_BRIDGE:
        print("SMOKE_NAV_BRIDGE_OPEN")
    else:
        push_error("Bridge mask missing or blocked")
    var trial: PackedVector2Array = nav.get_point_path(spawn, Vector2i(185, 61))
    if trial.size() > 10:
        print("SMOKE_NAV_ROUTE_FOUND")
    else:
        push_error("Navigation path test failed")
    if nav_size == EXPECTED_NAV_SIZE and WORLD_SIZE == Vector2(12800.0, 7200.0):
        print("SMOKE_NAV_FOUR_SECTORS")
    else:
        push_error("Expanded world size failed")
    # v0.3.4: explicit water / bridge tests against artwork-aligned river cells.
    var nw_river: Vector2i = Vector2i(85, 95)
    var eastern_river: Vector2i = Vector2i(348, 125)
    var western_bridge: Vector2i = Vector2i(60, 76)
    if (nav.is_point_solid(nw_river) and nav.is_point_solid(eastern_river)
        and not nav.is_point_solid(western_bridge)
        and int(nav_types[western_bridge.y * nav_size.x + western_bridge.x]) == CELL_BRIDGE):
        print("SMOKE_NAV_WATER_BARRIER_FIXED")
    else:
        push_error("Water barrier mismatch or bridge closed")
    # Check actual traversability across the NEW seams, not merely within the old sector.
    var east: Vector2i = Vector2i(310, 56)
    var south: Vector2i = Vector2i(100, 178)
    if (
        not nav.is_point_solid(east)
        and not nav.is_point_solid(south)
        and nav.get_point_path(spawn, east).size() > 30
        and nav.get_point_path(spawn, south).size() > 30
    ):
        print("SMOKE_NAV_CROSS_SECTOR_ROUTES")
        print("SMOKE_NAV_UNIQUE_WORLD")
    else:
        push_error("Expanded sectors are not connected by walkable routes")

func _classify_color(p: Color) -> int:
    # Colors in authored grid are RGB primaries; no interpolation is used here.
    if p.r < 0.18 and p.g < 0.18 and p.b < 0.18:
        return CELL_HOUSE
    if p.b > 0.72 and p.r < 0.20:
        return CELL_WATER
    if p.r > 0.72 and p.g > 0.72 and p.b < 0.25:
        return CELL_BRIDGE
    if p.r > 0.72 and p.g < 0.25 and p.b < 0.25:
        return CELL_ROAD
    if p.g > 0.72 and p.r < 0.25 and p.b < 0.25:
        return CELL_WOODS
    return CELL_FIELD

func _resize_camera() -> void:
    if not is_instance_valid(camera):
        return
    var viewport: Vector2 = get_viewport_rect().size
    _cancel_touch_gesture()
    ui_touch_ids.clear()
    var previous_min: float = camera_min_zoom
    var previous_zoom: float = camera.zoom.x
    # Preserve the original zoom limits and scale relative to a resized viewport.
    camera_min_zoom = maxf(viewport.x / WORLD_SIZE.x, viewport.y / WORLD_SIZE.y)
    var sector_zoom: float = maxf(viewport.x / SECTOR_SIZE.x, viewport.y / SECTOR_SIZE.y)
    camera_max_zoom = maxf(camera_min_zoom * 3.0, sector_zoom * 3.0)
    var new_zoom: float = maxf(sector_zoom, camera_min_zoom)
    if camera_view_initialized and previous_min > 0.0:
        new_zoom = previous_zoom * camera_min_zoom / previous_min
    camera.zoom = Vector2.ONE * clampf(new_zoom, camera_min_zoom, camera_max_zoom)
    camera_view_initialized = true
    _clamp_camera()
    _layout_camera_controls()

func _create_camera_controls() -> void:
    camera_controls = CanvasLayer.new()
    camera_controls.name = "CameraControls"
    camera_controls.layer = 20
    add_child(camera_controls)
    focus_button = Button.new()
    focus_button.name = "FocusMarker"
    focus_button.text = "К ШАРИКУ"
    focus_button.tooltip_text = "Вернуть камеру к шарику"
    focus_button.focus_mode = Control.FOCUS_NONE
    focus_button.mouse_filter = Control.MOUSE_FILTER_STOP
    focus_button.add_theme_font_size_override("font_size", 28)
    focus_button.add_theme_color_override("font_color", Color("#ecf5eb"))
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color(0.035, 0.07, 0.075, 0.94)
    normal.border_color = Color(0.40, 0.62, 0.54, 0.85)
    normal.set_border_width_all(2)
    normal.set_corner_radius_all(14)
    focus_button.add_theme_stylebox_override("normal", normal)
    var pressed := normal.duplicate() as StyleBoxFlat
    pressed.bg_color = Color(0.13, 0.25, 0.22, 0.97)
    focus_button.add_theme_stylebox_override("pressed", pressed)
    focus_button.add_theme_stylebox_override("hover", normal.duplicate())
    camera_controls.add_child(focus_button)
    focus_button.pressed.connect(_focus_marker)
    _layout_camera_controls()

func _layout_camera_controls() -> void:
    if not is_instance_valid(focus_button):
        return
    var viewport: Vector2 = get_viewport_rect().size
    var margin: float = clampf(minf(viewport.x, viewport.y) * 0.035, 12.0, 40.0)
    focus_button.size = Vector2(minf(360.0, maxf(160.0, viewport.x - margin * 2.0)), minf(112.0, maxf(56.0, viewport.y - margin * 2.0)))
    focus_button.position = Vector2(viewport.x - focus_button.size.x - margin, margin)

func _focus_marker() -> void:
    _cancel_touch_gesture()
    if not is_instance_valid(camera):
        return
    camera.position = ball_pos
    _clamp_camera()

func _camera_button_contains(screen_point: Vector2) -> bool:
    return is_instance_valid(focus_button) and focus_button.visible and focus_button.get_global_rect().has_point(screen_point)

func _zoom_camera_at(screen_point: Vector2, factor: float) -> void:
    _transform_camera(screen_point, screen_point, factor)

func _transform_camera(old_screen_center: Vector2, new_screen_center: Vector2, factor: float) -> void:
    if not is_instance_valid(camera) or not is_finite(factor) or factor <= 0.0:
        return
    var anchor: Vector2 = _screen_to_world(old_screen_center)
    var new_zoom: float = clampf(camera.zoom.x * factor, camera_min_zoom, camera_max_zoom)
    camera.zoom = Vector2.ONE * new_zoom
    camera.position = anchor - (new_screen_center - get_viewport_rect().size * 0.5) / new_zoom
    _clamp_camera()

func _cancel_touch_gesture() -> void:
    touch_points.clear()
    touch_down = false
    touch_moved = false
    gesture_was_multi = false
    single_touch_index = -1
    pinch_ids = Vector2i(-1, -1)
    pinch_distance = 0.0

func _rebase_pinch() -> void:
    if touch_points.size() < 2:
        pinch_ids = Vector2i(-1, -1)
        pinch_distance = 0.0
        return
    if not touch_points.has(pinch_ids.x) or not touch_points.has(pinch_ids.y):
        var ids: Array = touch_points.keys()
        ids.sort()
        pinch_ids = Vector2i(int(ids[0]), int(ids[1]))
    var first: Vector2 = touch_points[pinch_ids.x]
    var second: Vector2 = touch_points[pinch_ids.y]
    pinch_distance = first.distance_to(second)
    pinch_center = (first + second) * 0.5

func _begin_map_touch(e: InputEventScreenTouch) -> void:
    if touch_points.has(e.index):
        return
    touch_points[e.index] = e.position
    touch_down = true
    if touch_points.size() == 1:
        single_touch_index = e.index
        touch_start = e.position
        touch_last = e.position
        touch_moved = false
        gesture_was_multi = false
    else:
        gesture_was_multi = true
        touch_moved = true
        _rebase_pinch()

func _finish_map_touch(e: InputEventScreenTouch, allow_tap: bool) -> void:
    if e.canceled:
        _cancel_touch_gesture()
        return
    if not touch_points.has(e.index):
        return
    var can_order: bool = allow_tap and touch_points.size() == 1 and not gesture_was_multi and not touch_moved and e.position.distance_to(touch_start) <= TAP_SLOP
    touch_points.erase(e.index)
    touch_down = not touch_points.is_empty()
    if touch_points.is_empty():
        _cancel_touch_gesture()
        if can_order:
            _request_move(e.position)
    elif touch_points.size() == 1:
        # After a pinch the remaining finger may pan, but cannot become a tap.
        gesture_was_multi = true
        touch_moved = true
        var ids: Array = touch_points.keys()
        single_touch_index = int(ids[0])
        touch_start = touch_points[single_touch_index]
        touch_last = touch_start
        pinch_ids = Vector2i(-1, -1)
        pinch_distance = 0.0
    else:
        _rebase_pinch()

func _drag_map_touch(e: InputEventScreenDrag) -> void:
    if not touch_points.has(e.index):
        return
    var old_position: Vector2 = touch_points[e.index]
    touch_points[e.index] = e.position
    if touch_points.size() >= 2:
        if e.index != pinch_ids.x and e.index != pinch_ids.y:
            return
        var first: Vector2 = touch_points[pinch_ids.x]
        var second: Vector2 = touch_points[pinch_ids.y]
        var new_distance: float = first.distance_to(second)
        var new_center: Vector2 = (first + second) * 0.5
        var factor := 1.0
        if pinch_distance >= MIN_PINCH_DISTANCE and new_distance >= MIN_PINCH_DISTANCE:
            factor = new_distance / pinch_distance
        _transform_camera(pinch_center, new_center, factor)
        pinch_distance = new_distance
        pinch_center = new_center
    else:
        if e.position.distance_to(touch_start) > TAP_SLOP:
            touch_moved = true
        if touch_moved:
            camera.position -= (e.position - old_position) / camera.zoom
            _clamp_camera()
        touch_last = e.position

func _input(event: InputEvent) -> void:
    # GUI can consume a release over the button before _unhandled_input sees it.
    # Track those cases here without intercepting the Button's normal GUI input.
    if event is InputEventScreenTouch:
        var e := event as InputEventScreenTouch
        if e.pressed and _camera_button_contains(e.position):
            ui_touch_ids[e.index] = true
            _cancel_touch_gesture()
        elif ui_touch_ids.has(e.index):
            if not e.pressed or e.canceled:
                ui_touch_ids.erase(e.index)
                _cancel_touch_gesture()
        elif not e.pressed and touch_points.has(e.index) and _camera_button_contains(e.position):
            _finish_map_touch(e, false)
            get_viewport().set_input_as_handled()
    elif event is InputEventScreenDrag:
        var e := event as InputEventScreenDrag
        if touch_points.has(e.index) and _camera_button_contains(e.position):
            _drag_map_touch(e)
            get_viewport().set_input_as_handled()

func _clamp_camera() -> void:
    if not is_instance_valid(camera):
        return
    var half_view: Vector2 = get_viewport_rect().size * 0.5 / camera.zoom
    camera.position.x = clampf(camera.position.x, minf(half_view.x, WORLD_SIZE.x * 0.5), maxf(WORLD_SIZE.x - half_view.x, WORLD_SIZE.x * 0.5))
    camera.position.y = clampf(camera.position.y, minf(half_view.y, WORLD_SIZE.y * 0.5), maxf(WORLD_SIZE.y - half_view.y, WORLD_SIZE.y * 0.5))

func _cell_from_world(p: Vector2) -> Vector2i:
    return Vector2i(floori(p.x / nav_cell.x), floori(p.y / nav_cell.y))

func _inside(cell: Vector2i) -> bool:
    return cell.x >= 0 and cell.y >= 0 and cell.x < nav_size.x and cell.y < nav_size.y

func _type_at(p: Vector2) -> int:
    var cell: Vector2i = _cell_from_world(p)
    if not _inside(cell):
        return CELL_HOUSE
    return int(nav_types[cell.y * nav_size.x + cell.x])

func _request_move(screen_point: Vector2) -> void:
    var world: Vector2 = _screen_to_world(screen_point)
    var dst: Vector2i = _cell_from_world(world)
    if not _inside(dst) or nav.is_point_solid(dst):
        _reject(world)
        return
    var src: Vector2i = _cell_from_world(ball_pos)
    if not _inside(src) or nav.is_point_solid(src):
        _reject(world)
        return
    var result: PackedVector2Array = nav.get_point_path(src, dst)
    if result.is_empty():
        _reject(world)
        return
    # Defence in depth: a route must never contain a water or building cell.
    for waypoint in result:
        var waypoint_cell: Vector2i = _cell_from_world(waypoint)
        if not _inside(waypoint_cell) or nav.is_point_solid(waypoint_cell):
            _reject(world)
            return
    path = result
    path_next = 1 if path.size() > 1 else 0
    blocked_timer = 0.0
    queue_redraw()

func _screen_to_world(screen_point: Vector2) -> Vector2:
    var center: Vector2 = get_viewport_rect().size * 0.5
    return camera.position + (screen_point - center) / camera.zoom

func _reject(world: Vector2) -> void:
    blocked_at = world
    blocked_timer = 0.7
    queue_redraw()

func _process(delta: float) -> void:
    if blocked_timer > 0.0:
        blocked_timer = maxf(0.0, blocked_timer - delta)
        queue_redraw()
    if path_next >= path.size() or path.size() == 0:
        return
    var point: Vector2 = path[path_next]
    var movement_scale := 1.0
    match _type_at(ball_pos):
        CELL_ROAD:
            movement_scale = 1.4
        CELL_WOODS:
            movement_scale = 0.65
        CELL_FIELD:
            movement_scale = 0.9
        CELL_BRIDGE:
            movement_scale = 1.0
    var step: float = 280.0 * movement_scale * minf(delta, 0.08)
    ball_pos = ball_pos.move_toward(point, step)
    if ball_pos.distance_to(point) < 0.1:
        path_next += 1
        if path_next >= path.size():
            path.clear()
            path_next = 0
    queue_redraw()

func _draw() -> void:
    if path.size() > 0 and path_next < path.size():
        var points := PackedVector2Array([ball_pos])
        for i in range(path_next, path.size()):
            points.append(path[i])
        if points.size() > 1:
            draw_polyline(points, Color(0.18, 0.94, 0.72, 0.75), 9.0, true)
    # World-space ring, intentionally neutral test marker rather than a soldier.
    draw_circle(ball_pos + Vector2(10, 13), 52, Color(0.01, 0.03, 0.04, 0.55))
    draw_circle(ball_pos, 48, Color(0.035, 0.22, 0.22, 0.93))
    draw_circle(ball_pos, 38, Color(0.30, 0.98, 0.78))
    draw_circle(ball_pos + Vector2(-9, -9), 12, Color(0.92, 1.0, 0.95, 0.90))
    if blocked_timer > 0:
        draw_arc(blocked_at, 70.0 + (0.7-blocked_timer)*25.0, 0.0, TAU, 36, Color(1.0, 0.29, 0.23, blocked_timer), 12.0)

func _unhandled_input(event: InputEvent) -> void:
    if returning:
        return
    if event.is_action_pressed("ui_cancel"):
        _return_to_menu()
        get_viewport().set_input_as_handled()
        return
    if event is InputEventScreenTouch:
        var e := event as InputEventScreenTouch
        if e.canceled:
            _cancel_touch_gesture()
        elif ui_touch_ids.has(e.index) or not ui_touch_ids.is_empty():
            pass
        elif e.pressed:
            if not _camera_button_contains(e.position):
                _begin_map_touch(e)
        else:
            _finish_map_touch(e, not _camera_button_contains(e.position))
        get_viewport().set_input_as_handled()
    elif event is InputEventScreenDrag:
        var e := event as InputEventScreenDrag
        if ui_touch_ids.is_empty():
            _drag_map_touch(e)
        get_viewport().set_input_as_handled()
    elif event is InputEventMouseButton:
        var e := event as InputEventMouseButton
        if OS.get_name() == "Android" or e.device < 0 or touch_down:
            return
        # Desktop / debugging support; Android touch is processed above.
        if e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not touch_down:
            _request_move(e.position)
            get_viewport().set_input_as_handled()
        elif e.pressed and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
            var scale_factor := 1.16 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.16
            _zoom_camera_at(e.position, scale_factor)
            get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_GO_BACK_REQUEST:
        _return_to_menu()
    elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
        _cancel_touch_gesture()
        ui_touch_ids.clear()

func _return_to_menu() -> void:
    _cancel_touch_gesture()
    ui_touch_ids.clear()
    if returning:
        return
    returning = true
    call_deferred("_open_menu")

func _open_menu() -> void:
    if is_inside_tree():
        get_tree().change_scene_to_file(MENU_SCENE)
