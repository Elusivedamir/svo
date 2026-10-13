extends RefCounted

# Deterministic fixed-step simulation with shared current sector ownership.
const STEP := 0.05
const CELL_ROAD := 1
const CELL_WOODS := 2
const CELL_HOUSE := 3
const CELL_WATER := 4
const CELL_BRIDGE := 5

var nav: AStarGrid2D
var nav_types := PackedByteArray()
var world_size := Vector2(12800.0, 7200.0)
var nav_size := Vector2i.ZERO
var nav_cell := Vector2.ONE
var boundary_x := 6400.0
var visibility: RefCounted
var config: Dictionary = {}
var units: Array = []
var structures: Array = []
var sectors: Array = []
var drone: Dictionary = {}
var phase := "prepare"
var paused := false
var weather := "clear"
var time_of_day := "day"
var supplies: Array = [100.0, 100.0]
var winner := -1
var elapsed := 0.0
var victory_hold: Array = [0.0, 0.0]
var ai_enabled := true
var combat_enabled := true
var last_error := ""
var last_notice := ""
var _accumulator := 0.0
var _ai_timer := 0.0
var _reachable := PackedByteArray()

func _number(key: String, fallback: float) -> float:
    return float(config.get(key, fallback))

func setup(nav_grid: AStarGrid2D, types: PackedByteArray, world: Vector2, visibility_ref: RefCounted, settings: Dictionary) -> void:
    nav = nav_grid
    nav_types = types
    world_size = world
    nav_size = nav.region.size if nav != null else Vector2i.ZERO
    nav_cell = world_size / Vector2(nav_size) if nav_size.x > 0 and nav_size.y > 0 else Vector2.ONE
    boundary_x = world_size.x * 0.5
    visibility = visibility_ref
    config = settings.duplicate(true)
    weather = str(config.get("weather", "clear"))
    time_of_day = str(config.get("time_of_day", "day"))
    supplies = [_number("initial_supplies", 100.0), _number("initial_supplies", 100.0)]
    units.clear()
    structures.clear()
    sectors.clear()
    phase = "prepare"
    paused = false
    ai_enabled = true
    combat_enabled = true
    winner = -1
    elapsed = 0.0
    victory_hold = [0.0, 0.0]
    _accumulator = 0.0
    _ai_timer = 0.0
    last_error = ""
    last_notice = ""
    _build_reachable()
    var sector_size := world_size / Vector2(4.0, 2.0)
    for row in range(2):
        for column in range(4):
            var rect := Rect2(Vector2(column, row) * sector_size, sector_size)
            var point := _nearest_legal(rect.get_center(), -1, rect)
            sectors.append({"id": row * 4 + column, "rect": rect, "owner": 0 if column < 2 else 1,
                "weight": 1.0, "capture_progress": 0.0, "capturing_side": -1, "pos": point,
                "label": "Участок %d" % (row * 4 + column + 1), "woods": _terrain(point) == CELL_WOODS,
                "capture_pos": point})
    var homes: Array = [0, 1, 4, 5, 2, 3, 6, 7]
    var squad_size := maxi(1, int(config.get("squad_size", 6)))
    for id in range(8):
        var side := 0 if id < 4 else 1
        var sector_id := int(homes[id])
        var point: Vector2 = sectors[sector_id].pos
        var hp: Array = []
        for soldier in range(squad_size):
            hp.append(_number("soldier_hp", 100.0))
        units.append({"id": id, "side": side, "pos": point, "home": id, "hp": hp,
            "ammo": _number("squad_ammo", 180.0), "path": PackedVector2Array(), "path_next": 0,
            "order": "idle", "target_sector": sector_id, "capture_point": point, "fortified": true, "fortify_progress": 0.0,
            "fire_timer": 0.0, "anim_time": 0.0, "facing": Vector2.RIGHT if side == 0 else Vector2.LEFT,
            "shot_to": point, "shot_timer": 0.0, "last_damage_time": -1000.0})
        structures.append({"id": id, "side": side, "original_side": side, "pos": point,
            "kind": "bunker", "sector": sector_id, "rewarded": false})
    var post_point := _nearest_legal(world_size * Vector2(0.38, 0.5), 0)
    structures.append({"id": 8, "side": 0, "original_side": 0, "pos": post_point,
        "kind": "post", "sector": sector_at(post_point), "rewarded": false})
    drone = {"side": 0, "pos": post_point, "target": post_point, "state": "ready",
        "heading": 0.0, "charge": 100.0, "planned": false}
    if visibility != null:
        visibility.set("sectors", sectors)
    _sync_conditions()

func _sync_conditions() -> void:
    if visibility != null:
        visibility.set("weather", weather)
        visibility.set("time_of_day", time_of_day)

func _inside(point: Vector2) -> bool:
    return point.x >= 0.0 and point.y >= 0.0 and point.x < world_size.x and point.y < world_size.y

func _cell(point: Vector2) -> Vector2i:
    return Vector2i(floori(point.x / nav_cell.x), floori(point.y / nav_cell.y))

func _cell_inside(cell: Vector2i) -> bool:
    return cell.x >= 0 and cell.y >= 0 and cell.x < nav_size.x and cell.y < nav_size.y

func _terrain(point: Vector2) -> int:
    var cell := _cell(point)
    if not _cell_inside(cell):
        return CELL_HOUSE
    var index := cell.y * nav_size.x + cell.x
    return int(nav_types[index]) if index < nav_types.size() else 0

func _build_reachable() -> void:
    _reachable.resize(nav_size.x * nav_size.y)
    _reachable.fill(0)
    if nav == null or nav_size == Vector2i.ZERO:
        return
    var anchor := _cell(world_size * Vector2(0.25, 0.25))
    if nav.is_point_solid(anchor):
        for index in range(_reachable.size()):
            var candidate := Vector2i(index % nav_size.x, index / nav_size.x)
            if not nav.is_point_solid(candidate):
                anchor = candidate
                break
    var queue: Array[Vector2i] = [anchor]
    _reachable[anchor.y * nav_size.x + anchor.x] = 1
    var cursor := 0
    var offsets: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
    while cursor < queue.size():
        var current: Vector2i = queue[cursor]
        cursor += 1
        for offset in offsets:
            var cell: Vector2i = current + offset
            if not _cell_inside(cell):
                continue
            var index := cell.y * nav_size.x + cell.x
            if _reachable[index] != 0 or nav.is_point_solid(cell):
                continue
            _reachable[index] = 1
            queue.append(cell)

func legal_point(point: Vector2, side: int = -1) -> bool:
    if not _inside(point) or nav == null:
        return false
    if side == 0 and point.x >= boundary_x:
        return false
    if side == 1 and point.x < boundary_x:
        return false
    var cell := _cell(point)
    return _reachable[cell.y * nav_size.x + cell.x] != 0 and not nav.is_point_solid(cell)

func _nearest_legal(point: Vector2, side: int = -1, area: Rect2 = Rect2()) -> Vector2:
    var origin := _cell(point)
    for radius in range(maxi(nav_size.x, nav_size.y)):
        for dy in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                if maxi(absi(dx), absi(dy)) != radius:
                    continue
                var cell := origin + Vector2i(dx, dy)
                if not _cell_inside(cell):
                    continue
                var candidate: Vector2 = nav.get_point_position(cell)
                if area.has_area() and not area.has_point(candidate):
                    continue
                if legal_point(candidate, side):
                    return candidate
    return Vector2(-1.0, -1.0)

func alive_count(unit: Dictionary) -> int:
    var alive := 0
    for hp in unit.get("hp", []):
        if float(hp) > 0.0:
            alive += 1
    return alive

func unit_by_id(id: int) -> Dictionary:
    for unit in units:
        if int(unit.id) == id:
            return unit
    return {}

func sector_at(point: Vector2) -> int:
    if not _inside(point):
        return -1
    var column := clampi(floori(point.x / (world_size.x * 0.25)), 0, 3)
    var row := clampi(floori(point.y / (world_size.y * 0.5)), 0, 1)
    return row * 4 + column

func percent(side: int) -> float:
    var total := 0.0
    var owned := 0.0
    for sector in sectors:
        var weight := float(sector.weight)
        total += weight
        if int(sector.owner) == side:
            owned += weight
    return owned * 100.0 / total if total > 0.0 else 0.0

func _fail(message: String) -> bool:
    last_error = message
    return false

func can_place(point: Vector2, ignore_structure_id: int = -1) -> bool:
    if not legal_point(point, 0):
        return _fail("Нужна доступная суша на нашей половине")
    if _terrain(point) == CELL_BRIDGE:
        return _fail("Блиндаж и НП нельзя ставить на мосту")
    var snapped: Vector2 = nav.get_point_position(_cell(point))
    for structure in structures:
        if int(structure.side) == 0 and int(structure.id) != ignore_structure_id and snapped.distance_to(structure.pos) < 180.0:
            return _fail("Слишком близко к другой позиции")
    last_error = ""
    return true

func relocate(id: int, point: Vector2) -> bool:
    var unit := unit_by_id(id)
    if phase != "prepare" or unit.is_empty() or int(unit.side) != 0:
        return _fail("Расстановка доступна до начала боя")
    if not can_place(point, int(unit.home)):
        return false
    var snapped: Vector2 = nav.get_point_position(_cell(point))
    for structure in structures:
        if int(structure.id) == int(unit.home):
            structure.pos = snapped
            structure.sector = sector_at(snapped)
            break
    unit.pos = snapped
    unit.target_sector = sector_at(snapped)
    unit.fortified = true
    unit.path = PackedVector2Array()
    unit.path_next = 0
    last_error = ""
    return true

func relocate_post(point: Vector2) -> bool:
    if phase != "prepare":
        return _fail("Пост ставится на доступной земле нашей половины")
    if not can_place(point, 8):
        return false
    var snapped: Vector2 = nav.get_point_position(_cell(point))
    structures[8].pos = snapped
    structures[8].sector = sector_at(snapped)
    drone.pos = snapped
    if not bool(drone.planned):
        drone.target = snapped
    elif snapped.distance_to(drone.target) > _number("drone_range", 6000.0):
        drone.target = snapped
        drone.planned = false
    last_error = ""
    return true

func start_battle() -> bool:
    if phase != "prepare":
        return _fail("Бой уже начат")
    for unit in units:
        if not legal_point(unit.pos, int(unit.side)):
            return _fail("Проверьте расстановку позиций")
    if not legal_point(structures[8].pos, 0):
        return _fail("Наблюдательный пост недоступен")
    phase = "battle"
    paused = false
    _accumulator = 0.0
    _ai_timer = _number("ai_period", 2.0)
    if bool(drone.planned):
        drone.state = "flying" if Vector2(drone.pos).distance_to(drone.target) > 5.0 else "observing"
    last_error = ""
    last_notice = "Бой начат"
    _sync_conditions()
    return true

func order_move(id: int, point: Vector2, kind: String = "move") -> bool:
    var unit := unit_by_id(id)
    if phase != "battle" or paused or unit.is_empty() or alive_count(unit) == 0:
        return _fail("Приказ доступен живому отряду во время боя")
    if not legal_point(point):
        return _fail("Точка недоступна: вода, здание или край карты")
    var destination: Vector2 = nav.get_point_position(_cell(point))
    var route: PackedVector2Array = nav.get_point_path(_cell(unit.pos), _cell(destination))
    if route.is_empty():
        return _fail("Проход к точке не найден")
    unit.path = route
    unit.path_next = 1 if route.size() > 1 else route.size()
    unit.order = kind if kind in ["move", "capture"] else "move"
    unit.target_sector = sector_at(destination)
    unit.capture_point = destination
    unit.fortified = false
    unit.fortify_progress = 0.0
    last_error = ""
    return true

func order_capture(id: int, point: Vector2) -> bool:
    var sector_id := sector_at(point)
    if sector_id < 0:
        return _fail("Участок за границей карты")
    return order_move(id, point, "capture")

func order_stop(id: int) -> void:
    var unit := unit_by_id(id)
    if unit.is_empty() or phase != "battle":
        return
    unit.path = PackedVector2Array()
    unit.path_next = 0
    unit.order = "idle"
    unit.fortify_progress = 0.0

func order_fortify(id: int) -> bool:
    var unit := unit_by_id(id)
    if phase != "battle" or unit.is_empty() or alive_count(unit) == 0:
        return _fail("Нет живого отряда для обустройства")
    var sector_id := sector_at(unit.pos)
    if int(sectors[sector_id].owner) != int(unit.side) or _in_combat(unit):
        return _fail("Закрепиться можно на своей территории вне боя")
    if bool(unit.fortified):
        return _fail("Эта позиция уже обустроена")
    if float(supplies[int(unit.side)]) < _number("fortify_cost", 30.0):
        return _fail("Не хватает снабжения для обустройства")
    order_stop(id)
    unit.order = "fortify"
    unit.fortified = false
    unit.fortify_progress = 0.0
    last_error = ""
    return true

func _at_owned_bunker(unit: Dictionary) -> bool:
    var radius := _number("occupied_radius", 220.0)
    for structure in structures:
        if str(structure.kind) != "bunker" or int(structure.side) != int(unit.side):
            continue
        if Vector2(unit.pos).distance_squared_to(structure.pos) <= radius * radius:
            return true
    return false

func reinforce(id: int) -> bool:
    var unit := unit_by_id(id)
    if phase != "battle" or unit.is_empty() or alive_count(unit) == 0:
        return _fail("Полностью погибший отряд нельзя восстановить")
    if _moving(unit) or _in_combat(unit) or not _at_owned_bunker(unit):
        return _fail("Пополнение доступно у занятого блиндажа вне боя")
    var side := int(unit.side)
    var cost := _number("reinforce_cost", 20.0)
    if float(supplies[side]) < cost:
        return _fail("Не хватает снабжения")
    var hp: Array = unit.hp
    for index in range(hp.size()):
        if float(hp[index]) <= 0.0:
            hp[index] = _number("soldier_hp", 100.0)
            supplies[side] = float(supplies[side]) - cost
            last_error = ""
            return true
    return _fail("Отряд укомплектован")

func resupply(id: int) -> bool:
    var unit := unit_by_id(id)
    if phase != "battle" or unit.is_empty() or alive_count(unit) == 0 or _moving(unit) or _in_combat(unit) or not _at_owned_bunker(unit):
        return _fail("Боезапас пополняется у занятого блиндажа вне боя")
    var side := int(unit.side)
    var cost := _number("resupply_cost", 10.0)
    var maximum := _number("squad_ammo", 180.0)
    if float(unit.ammo) >= maximum:
        return _fail("Боезапас полный")
    if float(supplies[side]) < cost:
        return _fail("Не хватает снабжения")
    supplies[side] = float(supplies[side]) - cost
    unit.ammo = maximum
    last_error = ""
    return true

func assign_drone(point: Vector2, heading: float = 0.0) -> bool:
    if phase == "ended" or not _inside(point):
        return _fail("Точка дрона за границей карты")
    var post: Vector2 = structures[8].pos
    if post.distance_to(point) > _number("drone_range", 6000.0):
        return _fail("Точка за пределами связи с постом")
    if float(drone.charge) < 10.0:
        return _fail("Дрону нужно зарядить батарею")
    drone.target = point
    drone.heading = heading
    drone.planned = true
    if phase == "battle":
        drone.state = "flying" if Vector2(drone.pos).distance_to(point) > 5.0 else "observing"
    last_error = ""
    return true

func return_drone() -> void:
    drone.target = structures[8].pos
    drone.planned = false
    if phase == "prepare":
        drone.pos = structures[8].pos
        drone.state = "ready"
    elif phase == "battle":
        drone.state = "returning"

func _moving(unit: Dictionary) -> bool:
    var route: PackedVector2Array = unit.path
    return int(unit.path_next) < route.size()

func _visible_to(side: int, point: Vector2) -> bool:
    if visibility == null:
        return false
    return bool(visibility.call("is_visible", point, side, units, structures, drone, phase))

func _own_line_of_sight(origin: Vector2, destination: Vector2) -> bool:
    if visibility == null or not visibility.has_method("has_line_of_sight"):
        return false
    return bool(visibility.call("has_line_of_sight", origin, destination, false))

func _in_combat(unit: Dictionary) -> bool:
    if elapsed - float(unit.get("last_damage_time", -1000.0)) < 2.0:
        return true
    var radius := _number("weapon_range", 900.0)
    for enemy in units:
        if int(enemy.side) == int(unit.side) or alive_count(enemy) == 0:
            continue
        if Vector2(unit.pos).distance_squared_to(enemy.pos) <= radius * radius and _visible_to(int(unit.side), enemy.pos) and _own_line_of_sight(unit.pos, enemy.pos):
            return true
    return false

func advance(delta: float) -> void:
    _sync_conditions()
    if phase != "battle" or paused or delta <= 0.0:
        return
    _accumulator += delta
    while _accumulator + 0.000001 >= STEP and phase == "battle":
        _accumulator -= STEP
        _step(STEP)

func _step(delta: float) -> void:
    elapsed += delta
    for unit in units:
        unit.shot_timer = maxf(0.0, float(unit.shot_timer) - delta)
        unit.fire_timer = maxf(0.0, float(unit.fire_timer) - delta)
        if alive_count(unit) == 0:
            unit.path = PackedVector2Array()
            unit.path_next = 0
            unit.order = "idle"
            unit.fortified = false
            continue
        _move_unit(unit, delta)
        if str(unit.order) == "fortify" and not _moving(unit):
            if _in_combat(unit):
                unit.fortify_progress = 0.0
            else:
                unit.fortify_progress = float(unit.fortify_progress) + delta
                if float(unit.fortify_progress) + 0.000001 >= _number("fortify_seconds", 5.0):
                    var side := int(unit.side)
                    var cost := _number("fortify_cost", 30.0)
                    if float(supplies[side]) >= cost:
                        supplies[side] = float(supplies[side]) - cost
                        unit.fortified = true
                    unit.order = "idle"
    _advance_drone(delta)
    if combat_enabled:
        _combat()
    _capture(delta)
    _ai_timer -= delta
    if ai_enabled and _ai_timer <= 0.0:
        _ai_timer += maxf(STEP, _number("ai_period", 2.0))
        _decide_ai()
    _check_victory(delta)

func _move_unit(unit: Dictionary, delta: float) -> void:
    var route: PackedVector2Array = unit.path
    var next := int(unit.path_next)
    if next >= route.size():
        unit.path = PackedVector2Array()
        unit.path_next = 0
        if str(unit.order) == "move":
            unit.order = "idle"
        return
    var movement_scale := _number("field_speed", 0.7)
    match _terrain(unit.pos):
        CELL_ROAD: movement_scale = _number("road_speed", 1.0)
        CELL_WOODS: movement_scale = _number("woods_speed", 0.35)
        CELL_BRIDGE: movement_scale = _number("bridge_speed", 0.8)
    var remaining := _number("movement_speed", 280.0) * movement_scale * delta
    var position: Vector2 = unit.pos
    while next < route.size() and remaining > 0.0:
        var difference := route[next] - position
        var distance := difference.length()
        if distance <= 0.001:
            next += 1
            continue
        unit.facing = difference / distance
        if distance <= remaining:
            position = route[next]
            next += 1
            remaining -= distance
        else:
            position += difference / distance * remaining
            remaining = 0.0
    unit.pos = position
    unit.path_next = next
    unit.anim_time = float(unit.anim_time) + delta
    if next >= route.size() and str(unit.order) == "move":
        unit.order = "idle"
    if next >= route.size():
        unit.path = PackedVector2Array()
        unit.path_next = 0

func _advance_drone(delta: float) -> void:
    var state := str(drone.state)
    if state == "flying" or state == "returning":
        var target: Vector2 = drone.target
        var position: Vector2 = drone.pos
        drone.pos = position.move_toward(target, _number("drone_speed", 650.0) * delta)
        if Vector2(drone.pos).distance_to(target) <= 0.1:
            drone.state = "charging" if state == "returning" else "observing"
    if state == "flying" or state == "observing":
        var duration := maxf(1.0, _number("drone_charge_seconds", 120.0))
        drone.charge = maxf(0.0, float(drone.charge) - 100.0 * delta / duration)
        var home: Vector2 = structures[8].pos
        var return_seconds := Vector2(drone.pos).distance_to(home) / maxf(1.0, _number("drone_speed", 650.0))
        if float(drone.charge) <= return_seconds * 100.0 / duration + 2.0:
            return_drone()
    elif state == "charging":
        drone.charge = minf(100.0, float(drone.charge) + _number("drone_recharge_rate", 8.0) * delta)
        if float(drone.charge) >= 100.0:
            drone.state = "ready"

func _target_for(unit: Dictionary) -> Dictionary:
    var selected: Dictionary = {}
    var best := _number("weapon_range", 900.0) ** 2.0
    for enemy in units:
        if int(enemy.side) == int(unit.side) or alive_count(enemy) == 0:
            continue
        var distance := Vector2(unit.pos).distance_squared_to(enemy.pos)
        if distance > best or not _visible_to(int(unit.side), enemy.pos) or not _own_line_of_sight(unit.pos, enemy.pos):
            continue
        selected = enemy
        best = distance
    return selected

func _cover(unit: Dictionary) -> float:
    if _at_owned_bunker(unit):
        return _number("bunker_cover", 0.55)
    if _terrain(unit.pos) == CELL_WOODS:
        return _number("woods_cover", 0.65)
    return _number("fortified_cover", 0.75) if bool(unit.fortified) else 1.0

func _combat() -> void:
    var pending: Dictionary = {}
    for unit in units:
        var alive := alive_count(unit)
        if alive == 0 or float(unit.ammo) < 1.0 or float(unit.fire_timer) > 0.000001:
            continue
        var target := _target_for(unit)
        if target.is_empty():
            continue
        var firing := mini(alive, floori(float(unit.ammo)))
        var distance := Vector2(unit.pos).distance_to(target.pos)
        var range_value := maxf(1.0, _number("weapon_range", 900.0))
        var accuracy := _number("weapon_accuracy", 0.6) * (1.0 - 0.35 * distance / range_value)
        if _moving(unit):
            accuracy *= _number("moving_accuracy", 0.7)
        var damage := firing * _number("weapon_damage", 12.0) * accuracy * _cover(target)
        var target_id := int(target.id)
        pending[target_id] = float(pending.get(target_id, 0.0)) + damage
        unit.ammo = float(unit.ammo) - firing
        unit.fire_timer = maxf(STEP, _number("weapon_period", 0.7))
        unit.shot_to = target.pos
        unit.shot_timer = 0.18
        unit.facing = (Vector2(target.pos) - Vector2(unit.pos)).normalized()
    # Apply simultaneous volleys so array order gives neither side an advantage.
    for id in pending:
        var target := unit_by_id(int(id))
        target.last_damage_time = elapsed
        var hp: Array = target.hp
        var remaining := float(pending[id])
        for index in range(hp.size()):
            if float(hp[index]) <= 0.0:
                continue
            var taken := minf(float(hp[index]), remaining)
            hp[index] = maxf(0.0, float(hp[index]) - taken)
            remaining -= taken
            if remaining <= 0.000001:
                break

func _capture(delta: float) -> void:
    var radius := _number("capture_radius", 400.0)
    var duration := maxf(STEP, _number("capture_seconds", 20.0))
    for sector in sectors:
        var capturing: Dictionary = {}
        for unit in units:
            if alive_count(unit) == 0 or _moving(unit) or str(unit.order) != "capture" or int(unit.target_sector) != int(sector.id):
                continue
            if Vector2(unit.pos).distance_squared_to(unit.capture_point) <= radius * radius:
                capturing = unit
                break
        if capturing.is_empty():
            sector.capture_progress = 0.0
            sector.capturing_side = -1
            continue
        var side := int(capturing.side)
        var capture_point: Vector2 = capturing.capture_point
        sector.capture_pos = capture_point
        var contested := _in_combat(capturing)
        for unit in units:
            if int(unit.side) != side and alive_count(unit) > 0 and Vector2(unit.pos).distance_squared_to(capture_point) <= radius * radius:
                contested = true
                break
        if contested:
            sector.capture_progress = 0.0
            sector.capturing_side = -1
            continue
        var hostile_bunker := false
        for structure in structures:
            if str(structure.kind) == "bunker" and int(structure.side) != side and Vector2(structure.pos).distance_squared_to(capture_point) <= radius * radius:
                hostile_bunker = true
                break
        if int(sector.owner) == side and not hostile_bunker:
            capturing.order = "idle"
            capturing.fortified = true
            sector.capture_progress = 0.0
            sector.capturing_side = -1
            continue
        if int(sector.capturing_side) != side:
            sector.capture_progress = 0.0
            sector.capturing_side = side
        sector.capture_progress = float(sector.capture_progress) + delta
        if float(sector.capture_progress) + 0.000001 < duration:
            continue
        sector.owner = side
        sector.capture_progress = 0.0
        sector.capturing_side = -1
        capturing.order = "idle"
        capturing.fortified = true
        for structure in structures:
            if str(structure.kind) != "bunker" or int(structure.sector) != int(sector.id):
                continue
            if capture_point.distance_squared_to(structure.pos) > radius * radius:
                continue
            structure.side = side
            if int(structure.original_side) != side and not bool(structure.rewarded):
                supplies[side] = float(supplies[side]) + _number("bunker_capture_reward", 100.0)
                structure.rewarded = true
        last_notice = "%s захвачен" % str(sector.label)

func _decide_ai() -> void:
    for unit in units:
        if int(unit.side) != 1 or alive_count(unit) == 0:
            continue
        var contact: Dictionary = {}
        var nearest := INF
        for enemy in units:
            if int(enemy.side) == 1 or alive_count(enemy) == 0 or not _visible_to(1, enemy.pos):
                continue
            var distance := Vector2(unit.pos).distance_squared_to(enemy.pos)
            if distance < nearest:
                contact = enemy
                nearest = distance
        if not contact.is_empty():
            if Vector2(unit.pos).distance_to(contact.pos) > _number("weapon_range", 900.0) * 0.75:
                order_move(int(unit.id), contact.pos)
            elif _moving(unit):
                order_stop(int(unit.id))
            continue
        if _moving(unit) or str(unit.order) in ["capture", "fortify"]:
            continue
        if _at_owned_bunker(unit) and not _in_combat(unit):
            if alive_count(unit) < int(config.get("squad_size", 6)):
                reinforce(int(unit.id))
            if float(unit.ammo) < _number("squad_ammo", 180.0) * 0.25:
                resupply(int(unit.id))
        # Only public terrain objectives are consulted here. No friendly
        # bunker or hidden friendly-unit coordinates enter this decision.
        var chosen := -1
        var best := INF
        for sector in sectors:
            if int(sector.owner) == 1:
                continue
            var score := Vector2(unit.pos).distance_to(sector.pos)
            score += 700.0 * absf(float(int(sector.id) / 4 - (int(unit.id) - 4) / 2))
            if score < best:
                best = score
                chosen = int(sector.id)
        if chosen >= 0:
            order_capture(int(unit.id), sectors[chosen].pos)

func _check_victory(delta: float) -> void:
    var living: Array = [0, 0]
    for unit in units:
        if alive_count(unit) > 0:
            living[int(unit.side)] = int(living[int(unit.side)]) + 1
    if int(living[0]) == 0 or int(living[1]) == 0:
        winner = -2 if int(living[0]) == 0 and int(living[1]) == 0 else (0 if int(living[1]) == 0 else 1)
        phase = "ended"
        return
    var threshold := _number("victory_percent", 70.0)
    for side in range(2):
        victory_hold[side] = float(victory_hold[side]) + delta if percent(side) >= threshold else 0.0
        if float(victory_hold[side]) + 0.000001 >= _number("victory_hold_seconds", 60.0):
            winner = side
            phase = "ended"
            return
