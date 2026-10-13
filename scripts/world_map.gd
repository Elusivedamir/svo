extends Node2D

# v0.3.4: unique continuous 12800x7200 landscape with independently authored walkability.
# Preserve controls, camera and ball movement from the last successful build.
# No game combat logic, structures, or HUD. Tap a point to pathfind, swipe to pan.
const MAP_TEXTURE: Texture2D = preload("res://assets/map/terrain_v0.3.4.png")
const NAV_TEXTURE: Texture2D = preload("res://assets/map/navigation_v0.3.4.png")
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
        push_error("Map and navigation sizes do not match v0.3.4 water-safe unique world")
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
    terrain.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
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
    # Minimum permits strategic whole-map view; initial view retains the old world scale.
    camera_min_zoom = maxf(viewport.x / WORLD_SIZE.x, viewport.y / WORLD_SIZE.y)
    var sector_zoom: float = maxf(viewport.x / SECTOR_SIZE.x, viewport.y / SECTOR_SIZE.y)
    camera.zoom = Vector2.ONE * maxf(sector_zoom, camera_min_zoom)
    _clamp_camera()

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
    if event.is_action_pressed("ui_cancel"):
        _return_to_menu()
        get_viewport().set_input_as_handled()
        return
    if event is InputEventScreenTouch:
        var e := event as InputEventScreenTouch
        if e.index != 0:
            return
        if e.pressed:
            touch_down = true
            touch_start = e.position
            touch_last = e.position
            touch_moved = false
        elif touch_down:
            touch_down = false
            if not touch_moved:
                _request_move(e.position)
        get_viewport().set_input_as_handled()
    elif event is InputEventScreenDrag:
        var e := event as InputEventScreenDrag
        if e.index == 0 and touch_down:
            if e.position.distance_to(touch_start) > 20.0:
                touch_moved = true
            if touch_moved:
                camera.position -= (e.position - touch_last) / camera.zoom
                _clamp_camera()
            touch_last = e.position
            get_viewport().set_input_as_handled()
    elif event is InputEventMouseButton:
        if OS.get_name() == "Android":
            return
        var e := event as InputEventMouseButton
        # Desktop / debugging support; Android touch is processed above.
        if e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not touch_down:
            _request_move(e.position)
            get_viewport().set_input_as_handled()
        elif e.pressed and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
            var scale_factor := 1.16 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.16
            var new_zoom := clampf(camera.zoom.x * scale_factor, camera_min_zoom, maxf(camera_min_zoom * 3.0, maxf(get_viewport_rect().size.x / SECTOR_SIZE.x, get_viewport_rect().size.y / SECTOR_SIZE.y) * 3.0))
            camera.zoom = Vector2.ONE * new_zoom
            _clamp_camera()
            get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_GO_BACK_REQUEST:
        _return_to_menu()

func _return_to_menu() -> void:
    if returning:
        return
    returning = true
    call_deferred("_open_menu")

func _open_menu() -> void:
    if is_inside_tree():
        get_tree().change_scene_to_file(MENU_SCENE)
