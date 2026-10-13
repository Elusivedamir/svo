extends SceneTree

# Exercise the production map, Android touch routing and movement frames.
# The local cut test proves this passage is a bridge, not a detour elsewhere.
const SPEC_PATH := "res://data/bridge_corridors_v0.5.1.json"
var world: Node2D
var failures: Array[String] = []
var check_count := 0

func _initialize() -> void:
    call_deferred("run_checks")

func verify(ok: bool, caption: String) -> void:
    check_count += 1
    print("PASS " if ok else "FAIL ", caption)
    if not ok:
        failures.append(caption)

func cell_from_pair(pair: Array) -> Vector2i:
    return Vector2i(int(pair[0]), int(pair[1]))

func point_for(cell: Vector2i) -> Vector2:
    return world.nav.get_point_position(cell)

func safe_point(point: Vector2) -> bool:
    var cell: Vector2i = world._cell_from_world(point)
    if not world._inside(cell) or world.nav.is_point_solid(cell):
        return false
    var kind: int = world._type_at(point)
    return kind != world.CELL_WATER and kind != world.CELL_HOUSE

func screen_for(point: Vector2) -> Vector2:
    return world.get_viewport_rect().size * 0.5 + (point - world.camera.position) * world.camera.zoom

func prepare_order(start: Vector2i, target: Vector2i) -> Vector2:
    world._cancel_touch_gesture()
    world.ui_touch_ids.clear()
    world.returning = false
    world._set_squad_selected(true)
    world.ball_pos = point_for(start)
    world.path.clear()
    world.path_next = 0
    world.blocked_timer = 0.0
    world.squad_notice_timer = 0.0
    world.camera.zoom = Vector2.ONE * world.camera_max_zoom
    world.camera.position = point_for(target)
    world._clamp_camera()
    world._update_squad_hud()
    return screen_for(point_for(target))

func touch_map(point: Vector2) -> void:
    var press := InputEventScreenTouch.new()
    press.index = 7
    press.position = root.get_screen_transform() * point
    press.pressed = true
    Input.parse_input_event(press)
    await process_frame
    var release := InputEventScreenTouch.new()
    release.index = 7
    release.position = root.get_screen_transform() * point
    release.pressed = false
    Input.parse_input_event(release)
    await process_frame

func route_is_safe(points: PackedVector2Array) -> bool:
    for waypoint in points:
        if not safe_point(waypoint):
            return false
    return true

func route_uses_deck(points: PackedVector2Array, deck: Dictionary) -> bool:
    for waypoint in points:
        if deck.has(world._cell_from_world(waypoint)):
            return true
    return false

func finish_movement(destination: Vector2i, deck: Dictionary) -> Dictionary:
    var ticks := 0
    var unsafe_steps := 0
    var deck_steps := 0
    while not world.path.is_empty() and ticks < 40000:
        world._process(1.0 / 60.0)
        if not safe_point(world.ball_pos):
            unsafe_steps += 1
        if deck.has(world._cell_from_world(world.ball_pos)):
            deck_steps += 1
        ticks += 1
    return {
        "arrived": world.path.is_empty() and world.ball_pos.distance_to(point_for(destination)) < 0.1,
        "unsafe_steps": unsafe_steps,
        "deck_steps": deck_steps
    }

func local_grid(rect: Rect2i) -> AStarGrid2D:
    var grid := AStarGrid2D.new()
    grid.region = rect
    grid.cell_size = world.nav_cell
    grid.offset = world.nav_cell * 0.5
    grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
    grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
    grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
    grid.update()
    for y in range(rect.position.y, rect.end.y):
        for x in range(rect.position.x, rect.end.x):
            var cell := Vector2i(x, y)
            grid.set_point_solid(cell, world.nav.is_point_solid(cell))
            grid.set_point_weight_scale(cell, world.nav.get_point_weight_scale(cell))
    return grid

func run_checks() -> void:
    world = load("res://scenes/world_map.tscn").instantiate()
    root.add_child(world)
    world.set_process(false)
    await process_frame
    if world.nav == null or world.camera == null:
        verify(false, "actual world and navigation initialize")
        call_deferred("finish")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SPEC_PATH))
    if not parsed is Dictionary or not parsed.has("bridges") or parsed.bridges.is_empty():
        verify(false, "bridge regression specification loads")
        call_deferred("finish")
        return
    var spec: Dictionary = parsed
    verify(world.nav_size == cell_from_pair(spec.navigation_size), "bridge specification uses actual navigation dimensions")
    for bridge in spec.bridges:
        await test_bridge(bridge)
    call_deferred("finish")

func test_bridge(bridge: Dictionary) -> void:
    var bridge_name: String = bridge.name
    var a := cell_from_pair(bridge["from"])
    var b := cell_from_pair(bridge["to"])
    var deck: Dictionary = {}
    for pair in bridge.cells:
        deck[cell_from_pair(pair)] = true
    verify(not deck.is_empty(), "%s has an authored deck corridor" % bridge_name)
    verify(safe_point(point_for(a)) and safe_point(point_for(b)), "%s bank endpoints are walkable" % bridge_name)

    var deck_open := 0
    var deck_ordered := 0
    var deck_safe_routes := 0
    var remote_start := Vector2i(100, 56)
    for cell in deck:
        if world._type_at(point_for(cell)) == world.CELL_BRIDGE and not world.nav.is_point_solid(cell):
            deck_open += 1
        var screen: Vector2 = prepare_order(remote_start, cell)
        # A remote start makes this a movement order rather than selecting the
        # infantry marker when its screen-space hit rectangle is nearby.
        if world._squad_screen_rect().has_point(screen) or world._camera_button_contains(screen):
            continue
        await touch_map(screen)
        if not world.path.is_empty() and world.blocked_timer == 0.0 and world.path[-1].distance_to(point_for(cell)) < 0.1:
            deck_ordered += 1
            if route_is_safe(world.path):
                deck_safe_routes += 1
    verify(deck_open == deck.size(), "all %d %s deck cells are classified BRIDGE and open" % [deck.size(), bridge_name])
    verify(deck_ordered == deck.size(), "actual Android map taps accept every %s deck cell" % bridge_name)
    verify(deck_safe_routes == deck.size(), "every %s deck tap produces a route without water or buildings" % bridge_name)

    for direction in [[a, b], [b, a]]:
        var start: Vector2i = direction[0]
        var destination: Vector2i = direction[1]
        var screen: Vector2 = prepare_order(start, destination)
        verify(not world._squad_screen_rect().has_point(screen) and not world._camera_button_contains(screen), "%s %s->%s bank tap is clear of marker and HUD" % [bridge_name, start, destination])
        await touch_map(screen)
        var accepted: bool = not world.path.is_empty() and world.blocked_timer == 0.0
        verify(accepted and route_uses_deck(world.path, deck) and route_is_safe(world.path), "actual %s %s->%s tap routes across the new bridge" % [bridge_name, start, destination])
        var movement := finish_movement(destination, deck)
        verify(accepted and movement.arrived and movement.unsafe_steps == 0 and movement.deck_steps > 0, "actual %s %s->%s movement reaches opposite bank without entering water or buildings" % [bridge_name, start, destination])

    var river_blocked := 0
    var river_rejected := 0
    for pair in bridge.river_probes:
        var cell := cell_from_pair(pair)
        if world._type_at(point_for(cell)) == world.CELL_WATER and world.nav.is_point_solid(cell):
            river_blocked += 1
        var screen: Vector2 = prepare_order(remote_start, cell)
        var initial: Vector2 = world.ball_pos
        await touch_map(screen)
        world._process(1.0 / 60.0)
        if world.path.is_empty() and world.blocked_timer > 0.0 and world.ball_pos == initial:
            river_rejected += 1
    verify(not bridge.river_probes.is_empty() and river_blocked == bridge.river_probes.size(), "%s nearby river probes remain WATER and solid" % bridge_name)
    verify(river_rejected == bridge.river_probes.size(), "actual taps beside %s reject river movement and preserve position" % bridge_name)

    var region: Array = bridge.local_region
    var grid := local_grid(Rect2i(int(region[0]), int(region[1]), int(region[2]), int(region[3])))
    var forward: PackedVector2Array = grid.get_point_path(a, b)
    var backward: PackedVector2Array = grid.get_point_path(b, a)
    verify(not forward.is_empty() and not backward.is_empty() and route_uses_deck(forward, deck) and route_uses_deck(backward, deck), "%s local bank routes use the new deck in both directions" % bridge_name)
    for cell in deck:
        grid.set_point_solid(cell, true)
    verify(grid.get_point_path(a, b).is_empty() and grid.get_point_path(b, a).is_empty(), "closing only %s deck disconnects both banks locally" % bridge_name)
    for cell in deck:
        grid.set_point_solid(cell, world.nav.is_point_solid(cell))
    verify(not grid.get_point_path(a, b).is_empty() and not grid.get_point_path(b, a).is_empty(), "reopening %s deck restores both local bank routes" % bridge_name)

func finish() -> void:
    if failures.is_empty():
        print("PASS_BRIDGE_V051 checks=", check_count)
    else:
        push_error("Bridge v0.5.1 failures: %s" % [failures])
    if is_instance_valid(world):
        world.free()
    world = null
    quit(0 if failures.is_empty() else 1)
