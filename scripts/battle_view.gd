extends Node2D

# Procedural, animated top-down figures. A tactical badge is used only when
# the whole-map view is too small to distinguish the individual soldiers.
const FOG_INTERVAL := 0.5
const OVERVIEW_ZOOM := 0.23
const FORMATION := [Vector2(-48, -58), Vector2(48, -58), Vector2(-48, 0), Vector2(48, 0), Vector2(-48, 58), Vector2(48, 58)]
const FRIEND := Color("#69e9c1")
const ENEMY := Color("#ed8b74")

var model: RefCounted
var camera: Camera2D
var selected_id: int = 0
var selected_drone: bool = false
var target_mode: String = ""
var fog_enabled: bool = true
var fog_sprite: Sprite2D
var fog_texture: ImageTexture
var atmosphere: Polygon2D
var fog_elapsed: float = FOG_INTERVAL
var view_time := 0.0
var last_phase := ""
var last_conditions := ""
var _drone_sector_key := ""
var _drone_sector := PackedVector2Array()

func setup(battle_model: RefCounted, battle_camera: Camera2D) -> void:
    model = battle_model
    camera = battle_camera
    name = "BattleView"
    atmosphere = Polygon2D.new()
    atmosphere.name = "Atmosphere"
    atmosphere.z_index = -4
    var world: Vector2 = model.get("world_size")
    atmosphere.polygon = PackedVector2Array([Vector2.ZERO, Vector2(world.x, 0), world, Vector2(0, world.y)])
    add_child(atmosphere)
    fog_sprite = Sprite2D.new()
    fog_sprite.name = "CurrentObservationFog"
    fog_sprite.centered = false
    fog_sprite.z_index = -1
    # Nearest sampling keeps the displayed boundary inside the actual LOS mask.
    fog_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    add_child(fog_sprite)
    refresh_fog()
    queue_redraw()

func _phase_is_preparation() -> bool:
    return model != null and str(model.get("phase")) in ["prepare", "prep", "preparation"]

func _zoom() -> float:
    return maxf(0.01, camera.zoom.x) if is_instance_valid(camera) else 0.375

func _visible(point: Vector2) -> bool:
    if model == null:
        return false
    var visibility: RefCounted = model.get("visibility")
    if visibility == null:
        return false
    return visibility.is_visible(point, 0, model.get("units"), model.get("structures"), model.get("drone"), str(model.get("phase")))

func _alive(unit: Dictionary) -> bool:
    for hp in unit.get("hp", []):
        if float(hp) > 0.0:
            return true
    return false

func is_unit_visible(unit: Dictionary) -> bool:
    return _alive(unit) and (int(unit.get("side", -1)) == 0 or _visible(unit.get("pos", Vector2.ZERO)))

func is_structure_visible(structure: Dictionary) -> bool:
    if not bool(structure.get("placed", true)) or not bool(structure.get("deployed", true)):
        return false
    return _visible(structure.get("pos", Vector2.ZERO))

func visible_units() -> Array:
    var result: Array = []
    if model != null:
        for unit in model.get("units"):
            if is_unit_visible(unit):
                result.append(unit)
    return result

func visible_structures() -> Array:
    var result: Array = []
    if model != null:
        for structure in model.get("structures"):
            if is_structure_visible(structure):
                result.append(structure)
    return result

func _walkable(point: Vector2, footprint: float = 0.0) -> bool:
    if model == null:
        return false
    var world: Vector2 = model.get("world_size")
    var grid: AStarGrid2D = model.get("nav")
    if grid == null:
        return false
    var cell_size: Vector2 = world / Vector2(grid.region.size)
    var offsets := [Vector2.ZERO]
    if footprint > 0.0:
        offsets.append_array([Vector2(footprint, 0), Vector2(-footprint, 0), Vector2(0, footprint), Vector2(0, -footprint)])
    for offset in offsets:
        var sample: Vector2 = point + offset
        var cell := Vector2i(floori(sample.x / cell_size.x), floori(sample.y / cell_size.y))
        if not grid.region.has_point(cell) or grid.is_point_solid(cell):
            return false
    return true

func _formation_reachable(origin: Vector2, destination: Vector2) -> bool:
    # A legal endpoint across a thin river must not make a soldier jump there.
    var samples := maxi(1, ceili(origin.distance_to(destination) / 12.0))
    for index in range(samples + 1):
        if not _walkable(origin.lerp(destination, float(index) / samples)):
            return false
    return true

func soldier_positions(unit: Dictionary) -> Array:
    var result: Array = []
    var position: Vector2 = unit.get("pos", Vector2.ZERO)
    var facing: Vector2 = unit.get("facing", Vector2.RIGHT)
    var angle: float = facing.angle() + PI * 0.5 if facing.length_squared() > 0.001 else 0.0
    var hp: Variant = unit.get("hp", [])
    for index in range(hp.size()):
        if float(hp[index]) <= 0.0:
            continue
        var offset: Vector2 = FORMATION[index % FORMATION.size()].rotated(angle)
        var candidate := position + offset
        if not _walkable(candidate, 15.0) or not _formation_reachable(position, candidate):
            # Compress into a column on narrow bridge approaches; never paint
            # the figures on water just to keep a wide parade formation.
            candidate = position
            for scale_factor in [0.65, 0.35, 0.15]:
                var compressed: Vector2 = position + offset * scale_factor
                if _walkable(compressed, 10.0) and _formation_reachable(position, compressed):
                    candidate = compressed
                    break
        result.append(candidate)
    return result

func squad_hit_test(point: Vector2, zoom: float = -1.0) -> int:
    var actual_zoom := _zoom() if zoom <= 0.0 else maxf(0.01, zoom)
    var best := -1
    var best_distance := INF
    for unit in visible_units():
        var position: Vector2 = unit.get("pos", Vector2.ZERO)
        var distance := point.distance_squared_to(position)
        var radius := maxf(125.0, 42.0 / actual_zoom)
        if distance <= radius * radius and distance < best_distance:
            best_distance = distance
            best = int(unit.get("id", -1))
    return best

func structure_hit_test(point: Vector2) -> int:
    var best := -1
    var best_distance := INF
    for structure in visible_structures():
        var position: Vector2 = structure.get("pos", Vector2.ZERO)
        var distance := point.distance_squared_to(position)
        if distance <= 180.0 * 180.0 and distance < best_distance:
            best_distance = distance
            best = int(structure.get("id", -1))
    return best

func drone_hit_test(point: Vector2, zoom: float = -1.0) -> bool:
    if model == null:
        return false
    var drone: Dictionary = model.get("drone")
    if drone.is_empty() or int(drone.get("side", 0)) != 0:
        return false
    var actual_zoom := _zoom() if zoom <= 0.0 else maxf(0.01, zoom)
    var position: Vector2 = drone.get("pos", Vector2.ZERO)
    return point.distance_to(position) <= maxf(100.0, 42.0 / actual_zoom)

func refresh_fog() -> void:
    if model == null or not is_instance_valid(fog_sprite):
        return
    fog_sprite.visible = fog_enabled
    var visibility: RefCounted = model.get("visibility")
    if visibility != null and visibility.has_method("build_fog_image"):
        var image: Image = visibility.build_fog_image(model.get("units"), model.get("structures"), model.get("drone"), str(model.get("phase")))
        if fog_texture == null or fog_texture.get_size() != Vector2(image.get_size()):
            fog_texture = ImageTexture.create_from_image(image)
            fog_sprite.texture = fog_texture
            var world: Vector2 = model.get("world_size")
            fog_sprite.scale = world / Vector2(image.get_size())
        else:
            fog_texture.update(image)
    _update_atmosphere()
    last_phase = str(model.get("phase"))
    last_conditions = str(model.get("weather")) + "/" + str(model.get("time_of_day"))
    fog_elapsed = 0.0

func _update_atmosphere() -> void:
    if not is_instance_valid(atmosphere):
        return
    var shade := Color(0.06, 0.09, 0.15, 0.0)
    match str(model.get("time_of_day")):
        "dusk": shade = Color(0.22, 0.12, 0.20, 0.22)
        "night": shade = Color(0.025, 0.045, 0.12, 0.55)
    if str(model.get("weather")) == "fog":
        shade = shade.lerp(Color(0.66, 0.70, 0.68, 0.31), 0.65)
    elif str(model.get("weather")) == "rain":
        shade.a = maxf(shade.a, 0.15)
    atmosphere.color = shade

func _process(delta: float) -> void:
    if model == null:
        return
    view_time += delta
    fog_elapsed += delta
    var conditions := str(model.get("weather")) + "/" + str(model.get("time_of_day"))
    if fog_elapsed >= FOG_INTERVAL or last_phase != str(model.get("phase")) or last_conditions != conditions:
        refresh_fog()
    if is_instance_valid(fog_sprite):
        fog_sprite.visible = fog_enabled
    queue_redraw()

func _draw() -> void:
    if model == null:
        return
    var world: Vector2 = model.get("world_size")
    var visibility: RefCounted = model.get("visibility")
    var boundary := world.x * 0.5
    if visibility != null:
        boundary = float(visibility.get("boundary_x"))
    draw_line(Vector2(boundary, 0), Vector2(boundary, world.y), Color(0.93, 0.2, 0.16, 0.28), 1.8 / _zoom(), true)
    _draw_sector_selection()
    for structure in visible_structures():
        _draw_structure(structure)
    var selected: Dictionary = {}
    for unit in visible_units():
        if int(unit.get("id", -1)) == selected_id and int(unit.get("side", -1)) == 0:
            selected = unit
    if not selected.is_empty():
        _draw_route(selected)
    for unit in visible_units():
        _draw_unit(unit)
    _draw_drone()
    _draw_rain()

func _draw_sector_selection() -> void:
    # Only the currently occupied or observed capture location gets a marker.
    for sector in model.get("sectors"):
        var progress: float = float(sector.get("capture_progress", 0.0))
        var site: Vector2 = sector.get("capture_pos", sector.get("pos", Vector2.ZERO))
        if progress <= 0.0 or not _visible(site):
            continue
        var color: Color = FRIEND if int(sector.get("capturing_side", -1)) == 0 else ENEMY
        var radius := 135.0
        var duration: float = float(model.get("config").get("capture_seconds", 20.0))
        draw_arc(site, radius, -PI * 0.5, -PI * 0.5 + TAU * clampf(progress / maxf(0.05, duration), 0.0, 1.0), 40, color, 5.0 / _zoom(), true)

func _draw_structure(structure: Dictionary) -> void:
    var position: Vector2 = structure.get("pos", Vector2.ZERO)
    var color: Color = FRIEND if int(structure.get("side", 0)) == 0 else ENEMY
    draw_set_transform(position)
    if str(structure.get("kind", "bunker")) == "post":
        draw_circle(Vector2(8, 12), 77.0, Color(0.01, 0.02, 0.02, 0.40))
        draw_colored_polygon(PackedVector2Array([Vector2(-66, 44), Vector2(-66, -26), Vector2(0, -48), Vector2(66, -26), Vector2(66, 44)]), Color("#4a5942"))
        draw_line(Vector2(-67, -26), Vector2(0, -49), Color("#99a181"), 6.0, true)
        draw_line(Vector2(0, -49), Vector2(66, -26), Color("#99a181"), 6.0, true)
        draw_rect(Rect2(-20, -5, 40, 48), Color("#202b24"))
        draw_line(Vector2(75, 30), Vector2(75, -103), Color("#b6bcb0"), 5.0, true)
        draw_line(Vector2(52, -74), Vector2(98, -74), Color("#b6bcb0"), 4.0, true)
        draw_line(Vector2(60, 30), Vector2(75, -40), Color("#737c70"), 3.0, true)
        draw_line(Vector2(90, 30), Vector2(75, -40), Color("#737c70"), 3.0, true)
        draw_rect(Rect2(-84, 31, 24, 20), Color("#303d39"))
        draw_circle(Vector2(-74, 12), 11, Color("#c6ba93"))
        _draw_flag(Vector2(105, 12), color)
    else:
        # Earth berm, irregular sandbags, timber roof and a dark entrance.
        draw_circle(Vector2(10, 14), 91.0, Color(0.02, 0.02, 0.015, 0.45))
        draw_colored_polygon(PackedVector2Array([Vector2(-92, -26), Vector2(-54, -78), Vector2(50, -82), Vector2(96, -18), Vector2(76, 63), Vector2(-71, 69)]), Color("#6e6845"))
        draw_rect(Rect2(-61, -52, 122, 90), Color("#383d2e"))
        for index in range(7):
            draw_line(Vector2(-57 + index * 18, -48), Vector2(-57 + index * 18, 32), Color("#655b3d"), 12.0, true)
        draw_rect(Rect2(-26, 25, 52, 39), Color("#17211a"))
        draw_line(Vector2(-30, 24), Vector2(30, 24), Color("#a39365"), 8.0, true)
        for index in range(9):
            var angle := PI + float(index) * PI / 8.0
            var bag := Vector2(cos(angle) * 78.0, sin(angle) * 63.0 - 6.0)
            draw_circle(bag, 15.0, Color("#a59b6d"))
            draw_line(bag + Vector2(-9, 5), bag + Vector2(9, 5), Color("#77744e"), 2.0, true)
        _draw_flag(Vector2(99, 12), color)
    draw_set_transform(Vector2.ZERO)

func _draw_flag(position: Vector2, color: Color) -> void:
    draw_line(position + Vector2(0, 25), position + Vector2(0, -53), Color("#c9cbb4"), 4.0, true)
    draw_colored_polygon(PackedVector2Array([position + Vector2(0, -53), position + Vector2(37, -46), position + Vector2(0, -30)]), color)

func _draw_route(unit: Dictionary) -> void:
    var route: PackedVector2Array = unit.get("path", PackedVector2Array())
    var next: int = int(unit.get("path_next", 0))
    if next < route.size():
        var points := PackedVector2Array([unit.get("pos", Vector2.ZERO)])
        for index in range(next, route.size()):
            points.append(route[index])
        if points.size() > 1:
            draw_polyline(points, Color(0.40, 0.92, 0.76, 0.74), 3.0 / _zoom(), true)
        draw_circle(route[-1], 12.0 / _zoom(), FRIEND, false, 2.0 / _zoom(), true)

func _draw_unit(unit: Dictionary) -> void:
    var position: Vector2 = unit.get("pos", Vector2.ZERO)
    var side: int = int(unit.get("side", 0))
    var color: Color = FRIEND if side == 0 else ENEMY
    var selected: bool = side == 0 and int(unit.get("id", -1)) == selected_id
    if selected:
        draw_arc(position, 120.0, 0, TAU, 48, Color(color, 0.80), 2.0 / _zoom(), true)
        if target_mode != "":
            draw_arc(position, 137.0, 0, TAU, 48, Color(0.99, 0.87, 0.46, 0.85), 2.0 / _zoom(), true)
    if _zoom() < OVERVIEW_ZOOM:
        var radius := 16.0 / _zoom()
        draw_circle(position + Vector2(2, 3) / _zoom(), radius, Color(0.01, 0.02, 0.02, 0.7))
        draw_circle(position, radius, Color(0.03, 0.09, 0.08, 0.95))
        draw_circle(position, radius, color, false, 2.0 / _zoom(), true)
        _text(position + Vector2(-6, 6) / _zoom(), str(int(unit.get("id", 0)) % 4 + 1), 18.0 / _zoom(), color)
        return
    var positions := soldier_positions(unit)
    var facing: Vector2 = unit.get("facing", Vector2.RIGHT)
    var angle: float = facing.angle() + PI * 0.5 if facing.length_squared() > 0.001 else 0.0
    var moving: bool = str(unit.get("order", "idle")) in ["move", "capture"] and not (unit.get("path", PackedVector2Array()) as PackedVector2Array).is_empty()
    var crouched: bool = bool(unit.get("fortified", false)) and not moving
    var animation: float = float(unit.get("anim_time", view_time))
    for index in range(positions.size()):
        # A visible squad centre must not reveal members behind a wall/fog edge.
        if side == 1 and not _visible(positions[index]):
            continue
        _draw_soldier(positions[index], angle, color, side, animation * 8.0 + float(index) * 1.7, moving, crouched, float(unit.get("shot_timer", 0.0)) > 0.0)
    var count: int = positions.size()
    var label := ("ПЕХОТА " if side == 0 else "ПРОТИВНИК ") + str(int(unit.get("id", 0)) % 4 + 1)
    _text(position + Vector2(-94, -135), label, 28.0, Color(color, 0.95))
    _text(position + Vector2(70, -135), str(count), 27.0, Color("#eff7e9"))
    if float(unit.get("shot_timer", 0.0)) > 0.0:
        var target: Vector2 = unit.get("shot_to", position)
        # Both endpoints must currently be observable; no tracer points into fog.
        if _visible(position) and _visible(target):
            draw_line(position, target, Color(1.0, 0.88, 0.46, 0.5), 1.3 / _zoom(), true)

func _draw_soldier(position: Vector2, angle: float, team: Color, side: int, phase: float, moving: bool, crouched: bool, firing: bool) -> void:
    var stride := sin(phase) * 10.0 if moving else 0.0
    var bounce := absf(sin(phase)) * 2.0 if moving else 0.0
    var uniform := Color("#777b48") if side == 0 else Color("#74665b")
    var dark := Color("#343b29") if side == 0 else Color("#403832")
    draw_set_transform(position, angle)
    draw_circle(Vector2(5, 9), 23.0, Color(0.005, 0.008, 0.006, 0.5))
    # Separate boot/leg motion makes movement visible rather than sliding a token.
    draw_line(Vector2(-9, 9), Vector2(-11, 26 + stride), dark, 10.0, true)
    draw_line(Vector2(9, 9), Vector2(11, 26 - stride), dark, 10.0, true)
    draw_line(Vector2(-11, 26 + stride), Vector2(-11, 33 + stride), Color("#21291f"), 9.0, true)
    draw_line(Vector2(11, 26 - stride), Vector2(11, 33 - stride), Color("#21291f"), 9.0, true)
    var body_height := 25.0 if crouched else 31.0
    draw_rect(Rect2(-15, -16 - bounce, 30, body_height), uniform)
    draw_line(Vector2(-15, -8 - bounce), Vector2(-18, 9), uniform, 9.0, true)
    draw_line(Vector2(15, -8 - bounce), Vector2(19, -20), uniform, 9.0, true)
    draw_line(Vector2(-18, 9), Vector2(7, -15), Color("#c6b38b"), 6.0, true)
    draw_line(Vector2(19, -20), Vector2(9, -27), Color("#c6b38b"), 6.0, true)
    # Dark backpack and webbing remain distinct from the helmet and rifle.
    draw_rect(Rect2(-10, -5 - bounce, 20, 18), dark)
    draw_line(Vector2(-11, -15), Vector2(-6, 12), Color("#c0b68b"), 3.0, true)
    draw_line(Vector2(11, -15), Vector2(6, 12), Color("#c0b68b"), 3.0, true)
    draw_line(Vector2(-15, 8), Vector2(-8, 8), team, 5.0, true)
    draw_line(Vector2(8, -10), Vector2(8, -46), Color("#1d2422"), 5.0, true)
    draw_rect(Rect2(7, -25, 9, 10), Color("#4e4f3d"))
    draw_circle(Vector2(0, -20 - bounce), 12.0, Color("#333c2b"))
    draw_circle(Vector2(0, -22 - bounce), 10.0, uniform.lightened(0.14))
    draw_line(Vector2(-7, -23 - bounce), Vector2(7, -23 - bounce), Color("#b3b58b"), 2.0, true)
    if firing:
        draw_colored_polygon(PackedVector2Array([Vector2(8, -48), Vector2(1, -58), Vector2(8, -55), Vector2(15, -61), Vector2(13, -48)]), Color("#ffe08a"))
    draw_set_transform(Vector2.ZERO)

func _draw_drone() -> void:
    var drone: Dictionary = model.get("drone")
    if drone.is_empty():
        return
    if int(drone.get("side", 0)) != 0 and not _visible(drone.get("pos", Vector2.ZERO)):
        return
    var position: Vector2 = drone.get("pos", Vector2.ZERO)
    if selected_drone:
        _draw_drone_sector(drone)
        draw_circle(position, maxf(74.0, 25.0 / _zoom()), FRIEND, false, 2.0 / _zoom(), true)
        var target: Vector2 = drone.get("target", position)
        if target.distance_to(position) > 30.0 and str(drone.get("state", "ready")) in ["flying", "returning"]:
            draw_line(position, target, Color(FRIEND, 0.5), 2.0 / _zoom(), true)
            draw_circle(target, 12.0 / _zoom(), FRIEND, false, 2.0 / _zoom(), true)
    var scale_factor := maxf(1.0, 0.28 / _zoom())
    var heading: float = float(drone.get("heading", 0.0)) + PI * 0.5
    draw_set_transform(position + Vector2(24, 38), heading, Vector2.ONE * scale_factor)
    draw_circle(Vector2.ZERO, 42.0, Color(0.01, 0.02, 0.02, 0.26))
    draw_set_transform(position, heading, Vector2.ONE * scale_factor)
    draw_line(Vector2(-29, -25), Vector2(29, 25), Color("#e3e7e3"), 8.0, true)
    draw_line(Vector2(29, -25), Vector2(-29, 25), Color("#e3e7e3"), 8.0, true)
    for hub in [Vector2(-29, -25), Vector2(29, -25), Vector2(-29, 25), Vector2(29, 25)]:
        draw_circle(hub, 14.0, Color(0.8, 0.87, 0.85, 0.16))
        var blade := Vector2.from_angle(view_time * 30.0 + hub.x) * 14.0
        draw_line(hub - blade, hub + blade, Color("#d0d9d5"), 3.0, true)
        draw_circle(hub, 4.0, Color("#1c2e2e"))
    draw_rect(Rect2(-10, -16, 20, 32), Color("#e9eddf"))
    draw_circle(Vector2(0, -19), 5.0, Color("#294d52"))
    draw_set_transform(Vector2.ZERO)
    if selected_drone:
        _text(position + Vector2(-47, -78), "ДРОН", 30.0 / maxf(0.7, _zoom()), FRIEND)

func _draw_drone_sector(drone: Dictionary) -> void:
    if str(drone.get("state", "ready")) != "observing":
        return
    var visibility: RefCounted = model.get("visibility")
    if visibility == null:
        return
    var position: Vector2 = drone.get("pos", Vector2.ZERO)
    var radius: float = visibility.drone_radius()
    var half_angle: float = float(visibility.get("drone_angle")) * 0.5
    var heading: float = float(drone.get("heading", 0.0))
    var key := "%s/%s/%s/%s" % [position, radius, heading, visibility.drone_angle]
    if key == _drone_sector_key and not _drone_sector.is_empty():
        draw_colored_polygon(_drone_sector, Color(0.52, 0.85, 0.91, 0.085))
        var outline := _drone_sector.duplicate()
        outline.append(position)
        draw_polyline(outline, Color(0.52, 0.85, 0.91, 0.38), 1.5 / _zoom(), true)
        return
    var polygon := PackedVector2Array([position])
    for ray in range(37):
        var angle := heading - half_angle + 2.0 * half_angle * float(ray) / 36.0
        var direction := Vector2.from_angle(angle)
        var endpoint := position
        for sample in range(1, 33):
            var candidate := position + direction * radius * float(sample) / 32.0
            var source := {"pos": position, "radius": radius, "airborne": true, "heading": heading}
            if not visibility._source_sees(source, candidate):
                break
            endpoint = candidate
        polygon.append(endpoint)
    _drone_sector_key = key
    _drone_sector = polygon.duplicate()
    draw_colored_polygon(polygon, Color(0.52, 0.85, 0.91, 0.085))
    polygon.append(position)
    draw_polyline(polygon, Color(0.52, 0.85, 0.91, 0.38), 1.5 / _zoom(), true)

func _draw_rain() -> void:
    if str(model.get("weather")) != "rain" or not is_instance_valid(camera):
        return
    var extent := get_viewport_rect().size / _zoom()
    var origin := camera.position - extent * 0.5
    for index in range(42):
        var x := fposmod(float(index * 173) + view_time * 110.0, extent.x)
        var y := fposmod(float(index * 311) + view_time * 760.0, extent.y)
        var start := origin + Vector2(x, y)
        draw_line(start, start + Vector2(-6, 19) / _zoom(), Color(0.78, 0.87, 0.91, 0.27), 1.0 / _zoom(), true)

func _text(position: Vector2, content: String, size: float, color: Color) -> void:
    var font := ThemeDB.fallback_font
    var font_size := maxi(1, roundi(size))
    draw_string(font, position + Vector2(2, 3), content, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.01, 0.03, 0.025, 0.92))
    draw_string(font, position, content, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
