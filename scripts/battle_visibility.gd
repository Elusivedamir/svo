extends RefCounted

# Owned territory stays open until captured. Outside it only current observers
# reveal units and terrain. Combat still checks physical line of sight.
const CELL_WOODS := 2
const CELL_HOUSE := 3
const HIDDEN_ALPHA := 0.86

var weather := "clear"
var time_of_day := "day"
var boundary_x := 6400.0
var world_size := Vector2(12800.0, 7200.0)
var nav: AStarGrid2D
var nav_types := PackedByteArray()
var nav_size := Vector2i.ZERO
var nav_cell := Vector2.ONE
var obstacle_prefix := PackedInt32Array()
var prefix_width := 0
var infantry_view := 1100.0
var drone_view := 1900.0
var fortified_view_bonus := 0.25
var drone_angle := deg_to_rad(100.0)
var occupied_radius := 220.0
var woods_depth := 320.0
var drone_woods_depth := 180.0
var sectors: Array = []

func setup(nav_grid: AStarGrid2D, types: PackedByteArray, world: Vector2, config: Dictionary) -> void:
    nav = nav_grid
    nav_types = types
    world_size = world
    nav_size = nav.region.size if nav != null else Vector2i.ZERO
    nav_cell = world_size / Vector2(nav_size) if nav_size.x > 0 and nav_size.y > 0 else Vector2.ONE
    boundary_x = float(config.get("boundary_x", world_size.x * 0.5))
    infantry_view = float(config.get("infantry_view", 1100.0))
    drone_view = float(config.get("drone_view", 1900.0))
    fortified_view_bonus = float(config.get("fortified_view_bonus", 0.25))
    drone_angle = deg_to_rad(float(config.get("drone_angle", 100.0)))
    occupied_radius = float(config.get("occupied_radius", 220.0))
    woods_depth = float(config.get("woods_depth", 320.0))
    drone_woods_depth = float(config.get("drone_woods_depth", 180.0))
    weather = str(config.get("weather", "clear"))
    time_of_day = str(config.get("time_of_day", "day"))
    _build_obstacle_prefix()

func _build_obstacle_prefix() -> void:
    # Summed-area obstruction counts skip per-cell ray tracing through entirely
    # open areas. Map terrain is immutable after setup.
    prefix_width = nav_size.x + 1
    obstacle_prefix.resize(prefix_width * (nav_size.y + 1))
    obstacle_prefix.fill(0)
    for y in range(nav_size.y):
        var row_total := 0
        for x in range(nav_size.x):
            var index := y * nav_size.x + x
            if index < nav_types.size() and (nav_types[index] == CELL_HOUSE or nav_types[index] == CELL_WOODS):
                row_total += 1
            obstacle_prefix[(y + 1) * prefix_width + x + 1] = obstacle_prefix[y * prefix_width + x + 1] + row_total

func _box_has_obstacles(start: Vector2i, end: Vector2i) -> bool:
    var left := mini(start.x, end.x)
    var right := maxi(start.x, end.x) + 1
    var top := mini(start.y, end.y)
    var bottom := maxi(start.y, end.y) + 1
    if left < 0 or top < 0 or right > nav_size.x or bottom > nav_size.y:
        return true
    return obstacle_prefix[bottom * prefix_width + right] - obstacle_prefix[top * prefix_width + right] - obstacle_prefix[bottom * prefix_width + left] + obstacle_prefix[top * prefix_width + left] > 0

func _condition_factor() -> float:
    var rain_factor := 1.0
    match weather:
        "rain": rain_factor = 0.75
        "fog": rain_factor = 0.5
    var light_factor := 1.0
    match time_of_day:
        "dusk": light_factor = 0.7
        "night": light_factor = 0.45
    return rain_factor * light_factor

func _alive(unit: Dictionary) -> bool:
    var hit_points: Variant = unit.get("hp", [])
    for hp in hit_points:
        if float(hp) > 0.0:
            return true
    return false

func observation_radius(unit: Dictionary, structures: Array) -> float:
    # Fortification belongs to a living occupying group. The same bonus applies
    # after it prepares a forest/field position; abandoned sites never observe.
    var prepared := bool(unit.get("fortified", false))
    var route: PackedVector2Array = unit.get("path", PackedVector2Array())
    var moving: bool = int(unit.get("path_next", 0)) < route.size()
    if not prepared and not moving:
        for structure in structures:
            if int(structure.get("side", -1)) == int(unit.get("side", -2)):
                var position: Vector2 = unit.get("pos", Vector2.ZERO)
                if position.distance_squared_to(structure.get("pos", Vector2.ZERO)) <= occupied_radius * occupied_radius:
                    prepared = true
                    break
    var bonus := 1.0 + fortified_view_bonus if prepared else 1.0
    return infantry_view * _condition_factor() * bonus

func drone_radius() -> float:
    return drone_view * _condition_factor()

func _in_world(point: Vector2) -> bool:
    return point.x >= 0.0 and point.y >= 0.0 and point.x < world_size.x and point.y < world_size.y

func _cell(point: Vector2) -> Vector2i:
    return Vector2i(floori(point.x / nav_cell.x), floori(point.y / nav_cell.y))

func _terrain(cell: Vector2i) -> int:
    if cell.x < 0 or cell.y < 0 or cell.x >= nav_size.x or cell.y >= nav_size.y:
        return CELL_HOUSE
    var index := cell.y * nav_size.x + cell.x
    return int(nav_types[index]) if index < nav_types.size() else 0

func _line_clear(origin: Vector2, point: Vector2, airborne: bool) -> bool:
    if nav_size == Vector2i.ZERO:
        return true
    var start := _cell(origin)
    var end := _cell(point)
    if not _box_has_obstacles(start, end):
        return true
    var dx := absi(end.x - start.x)
    var dy := absi(end.y - start.y)
    var sx := 1 if start.x < end.x else -1
    var sy := 1 if start.y < end.y else -1
    var error := dx - dy
    var cell := start
    var wood_distance := 0.0
    var wood_limit := drone_woods_depth if airborne else woods_depth
    var step_distance := (nav_cell.x + nav_cell.y) * 0.5
    while cell != end:
        var previous := cell
        var twice := error * 2
        if twice > -dy:
            error -= dy
            cell.x += sx
        if twice < dx:
            error += dx
            cell.y += sy
        # Prevent looking diagonally through touching opaque building corners.
        if previous.x != cell.x and previous.y != cell.y:
            if _terrain(Vector2i(previous.x, cell.y)) == CELL_HOUSE and _terrain(Vector2i(cell.x, previous.y)) == CELL_HOUSE:
                return false
        var terrain_type := _terrain(cell)
        if terrain_type == CELL_HOUSE:
            return false
        if terrain_type == CELL_WOODS:
            wood_distance += step_distance * (1.414214 if previous.x != cell.x and previous.y != cell.y else 1.0)
            if wood_distance > wood_limit:
                return false
    return true

func has_line_of_sight(origin: Vector2, point: Vector2, is_drone: bool = false) -> bool:
    if not _in_world(origin) or not _in_world(point):
        return false
    return _line_clear(origin, point, is_drone)

func _source_sees(source: Dictionary, point: Vector2) -> bool:
    var origin: Vector2 = source.pos
    var offset := point - origin
    var radius: float = source.radius
    if offset.length_squared() > radius * radius:
        return false
    var airborne: bool = source.airborne
    if airborne and offset.length_squared() > 1.0:
        var direction := Vector2.from_angle(float(source.heading))
        if direction.dot(offset.normalized()) < cos(drone_angle * 0.5):
            return false
    return _line_clear(origin, point, airborne)

func observation_sources(side: int, units: Array, structures: Array, drone: Dictionary) -> Array:
    var sources: Array = []
    for unit in units:
        if int(unit.get("side", -1)) != side or not _alive(unit):
            continue
        var position: Vector2 = unit.get("pos", Vector2.ZERO)
        if _in_world(position):
            sources.append({"pos": position, "radius": observation_radius(unit, structures), "airborne": false, "heading": 0.0})
    if not drone.is_empty() and int(drone.get("side", 0)) == side and str(drone.get("state", "ready")) == "observing" and float(drone.get("charge", 0.0)) > 0.0:
        var position: Vector2 = drone.get("pos", Vector2.ZERO)
        if _in_world(position):
            sources.append({"pos": position, "radius": drone_radius(), "airborne": true, "heading": float(drone.get("heading", 0.0))})
    return sources

func is_visible(point: Vector2, side: int, units: Array, structures: Array, drone: Dictionary, phase: String) -> bool:
    if not _in_world(point):
        return false
    if phase == "prepare" or phase == "prep" or phase == "preparation":
        return point.x < boundary_x if side == 0 else point.x >= boundary_x
    if territory_visible(point, side):
        return true
    for source in observation_sources(side, units, structures, drone):
        if _source_sees(source, point):
            return true
    return false

func territory_visible(point: Vector2, side: int) -> bool:
    for sector in sectors:
        var rect: Rect2 = sector.get("rect", Rect2())
        if rect.has_point(point):
            return int(sector.get("owner", -1)) == side
    return false

func build_fog_image(units: Array, structures: Array, drone: Dictionary, phase: String, resolution: Vector2i = Vector2i(128, 72)) -> Image:
    resolution = Vector2i(maxi(1, resolution.x), maxi(1, resolution.y))
    var bytes := PackedByteArray()
    bytes.resize(resolution.x * resolution.y * 4)
    var hidden := roundi(HIDDEN_ALPHA * 255.0)
    for index in range(resolution.x * resolution.y):
        bytes[index * 4 + 3] = hidden
    var pixel_size := world_size / Vector2(resolution)
    if phase == "prepare" or phase == "prep" or phase == "preparation":
        for y in range(resolution.y):
            for x in range(resolution.x):
                if (float(x) + 0.5) * pixel_size.x < boundary_x:
                    bytes[(y * resolution.x + x) * 4 + 3] = 0
    else:
        for y in range(resolution.y):
            for x in range(resolution.x):
                var point := (Vector2(x, y) + Vector2.ONE * 0.5) * pixel_size
                if territory_visible(point, 0):
                    bytes[(y * resolution.x + x) * 4 + 3] = 0
        # Work only inside each source's bounding box. Unobserved pixels never
        # call LOS, and already revealed pixels skip overlapping observers.
        for source in observation_sources(0, units, structures, drone):
            var origin: Vector2 = source.pos
            var radius: float = source.radius
            var left := clampi(floori((origin.x - radius) / pixel_size.x), 0, resolution.x - 1)
            var right := clampi(ceili((origin.x + radius) / pixel_size.x), 0, resolution.x - 1)
            var top := clampi(floori((origin.y - radius) / pixel_size.y), 0, resolution.y - 1)
            var bottom := clampi(ceili((origin.y + radius) / pixel_size.y), 0, resolution.y - 1)
            for y in range(top, bottom + 1):
                for x in range(left, right + 1):
                    var index := (y * resolution.x + x) * 4 + 3
                    if bytes[index] == 0:
                        continue
                    var point := (Vector2(x, y) + Vector2.ONE * 0.5) * pixel_size
                    if _source_sees(source, point):
                        bytes[index] = 0
    return Image.create_from_data(resolution.x, resolution.y, false, Image.FORMAT_RGBA8, bytes)
