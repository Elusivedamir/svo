extends SceneTree

# Exercise the production scene and actual viewport GUI input routing.
var world: Node2D
var failures: Array[String] = []
var check_count: int = 0
var center: Vector2
var baseline_zoom: float
var target: Vector2
var target_screen: Vector2

func _initialize() -> void:
    call_deferred("run_checks")

func verify(ok: bool, caption: String) -> void:
    check_count += 1
    print("PASS " if ok else "FAIL ", caption)
    if not ok:
        failures.append(caption)

func route_touch(index: int, point: Vector2, pressed: bool, canceled: bool = false) -> void:
    var event := InputEventScreenTouch.new()
    event.index = index
    event.position = root.get_screen_transform() * point
    event.pressed = pressed
    event.canceled = canceled
    Input.parse_input_event(event)
    await process_frame

func route_drag(index: int, point: Vector2, relative: Vector2) -> void:
    var event := InputEventScreenDrag.new()
    event.index = index
    event.position = root.get_screen_transform() * point
    event.relative = root.get_screen_transform().basis_xform(relative)
    Input.parse_input_event(event)
    await process_frame

func tap(point: Vector2, index: int = 0) -> void:
    await route_touch(index, point, true)
    await route_touch(index, point, false)

func world_to_screen(point: Vector2) -> Vector2:
    return center + (point - world.camera.position) * world.camera.zoom

func refresh_hud() -> void:
    if world.has_method("_update_squad_hud"):
        world._update_squad_hud()

func reset_test() -> void:
    world._cancel_touch_gesture()
    world.ui_touch_ids.clear()
    world.returning = false
    world.ball_pos = world.nav.get_point_position(Vector2i(100, 56))
    world.path.clear()
    world.path_next = 0
    world.blocked_timer = 0.0
    world.camera.zoom = Vector2.ONE * baseline_zoom
    world.camera.position = world.ball_pos
    world._clamp_camera()
    world._set_squad_selected(true)
    refresh_hud()
    world.move_order_count = 0
    target_screen = world_to_screen(target)

func seeded_route() -> PackedVector2Array:
    var points: PackedVector2Array = world.nav.get_point_path(Vector2i(100, 56), Vector2i(185, 61))
    world.path = points.duplicate()
    world.path_next = 3
    refresh_hud()
    return points

func unchanged_route(points: PackedVector2Array) -> bool:
    return world.move_order_count == 0 and world.path == points and world.path_next == 3

func run_checks() -> void:
    world = load("res://tools/squad_v05_probe.gd").new()
    root.add_child(world)
    world.set_process(false)
    await process_frame
    center = world.get_viewport_rect().size * 0.5
    baseline_zoom = (world.camera_min_zoom + world.camera_max_zoom) * 0.5
    if world.nav == null or world.camera == null:
        verify(false, "real squad scene initializes")
        finish()
        return
    target = world.nav.get_point_position(Vector2i(110, 56))
    verify(not world.nav.is_point_solid(Vector2i(110, 56)), "order test destination is a real walkable cell")
    test_initial_hud()
    await test_selection_and_orders()
    await test_stop_and_focus()
    await test_hud_crossovers()
    await test_panel_input()
    test_physical_movement()
    call_deferred("finish")

func test_initial_hud() -> void:
    verify(world.squad_selected, "first squad starts selected")
    verify(world.focus_button.text == "К ОТРЯДУ", "camera button names the squad")
    verify(world.selection_button != null and world.stop_button != null and world.squad_status != null, "selection, stop and squad status controls exist")
    verify(world.stop_button.disabled, "stop starts disabled while squad is idle")
    var bounds: Rect2 = world.get_viewport_rect()
    var controls: Array[Button] = [world.focus_button, world.selection_button, world.stop_button]
    var valid := true
    for button in controls:
        valid = valid and button.mouse_filter == Control.MOUSE_FILTER_STOP
        valid = valid and bounds.encloses(button.get_global_rect()) and button.size.y >= 56.0
        valid = valid and world._camera_button_contains(button.get_global_rect().get_center())
    verify(valid, "all interactive squad HUD controls fit the viewport and block map input")
    var overlap := false
    for a in range(controls.size()):
        for b in range(a + 1, controls.size()):
            overlap = overlap or controls[a].get_global_rect().intersects(controls[b].get_global_rect())
    verify(not overlap, "HUD touch targets do not overlap")

func test_selection_and_orders() -> void:
    reset_test()
    world._set_squad_selected(false)
    await tap(world._squad_screen_rect().get_center())
    verify(world.squad_selected and world.move_order_count == 0 and world.path.is_empty(), "actual squad touch selects it without creating a movement route")

    reset_test()
    var points: PackedVector2Array = seeded_route()
    await tap(world._squad_screen_rect().get_center())
    verify(world.squad_selected and unchanged_route(points), "touching selected moving squad preserves its active route")

    reset_test()
    await tap(target_screen, 4)
    verify(world.move_order_count == 1 and not world.path.is_empty() and world.path[world.path.size() - 1].distance_to(target) < 0.1, "actual map tap issues exactly one order for selected squad")
    verify(not world.stop_button.disabled, "stop becomes available after a valid order")

    reset_test()
    points = seeded_route()
    var button_point: Vector2 = world.selection_button.get_global_rect().get_center()
    await tap(button_point)
    verify(not world.squad_selected and unchanged_route(points), "actual selection button deselects squad without interrupting route")
    verify(world.stop_button.disabled, "stop is disabled when squad is not selected")
    await tap(target_screen)
    verify(not world.squad_selected and unchanged_route(points), "map tap while unselected leaves existing route untouched")
    await tap(button_point)
    verify(world.squad_selected and unchanged_route(points), "selection button selects squad again without issuing an order")
    await tap(target_screen)
    verify(world.move_order_count == 1 and not world.path.is_empty(), "new map order works after selecting squad again")

    reset_test()
    world._set_squad_selected(false)
    world._request_move(target_screen)
    verify(world.path.is_empty(), "direct movement primitive also rejects unselected squad orders")

    reset_test()
    points = seeded_route()
    var marker_point: Vector2 = world._squad_screen_rect().get_center()
    await route_touch(0, marker_point, true)
    await route_drag(0, marker_point + Vector2(90.0, 40.0), Vector2(90.0, 40.0))
    await route_touch(0, marker_point + Vector2(90.0, 40.0), false)
    verify(unchanged_route(points), "drag starting on squad remains a camera gesture without an order")

    reset_test()
    world._set_squad_selected(false)
    var start := center - Vector2(120.0, 0.0)
    await route_touch(0, start, true)
    await route_touch(1, center + Vector2(120.0, 0.0), true)
    await route_drag(0, center - Vector2(180.0, 0.0), Vector2(-60.0, 0.0))
    await route_touch(1, center + Vector2(120.0, 0.0), false)
    await route_touch(0, center - Vector2(180.0, 0.0), false)
    verify(not world.squad_selected and world.move_order_count == 0 and world.path.is_empty(), "pinch across squad never selects it or creates an order")

func test_stop_and_focus() -> void:
    reset_test()
    var points: PackedVector2Array = seeded_route()
    var marker: Vector2 = world.ball_pos
    var stop_point: Vector2 = world.stop_button.get_global_rect().get_center()
    await tap(stop_point)
    verify(world.path.is_empty() and world.path_next == 0 and world.ball_pos == marker and world.move_order_count == 0, "actual stop touch clears route at current squad position without a map order")
    verify(world.stop_button.disabled, "stop disables after route is cleared")
    for tick in range(120):
        world._process(1.0 / 60.0)
    verify(world.ball_pos == marker, "stopped squad remains stationary on subsequent movement frames")
    await tap(stop_point)
    verify(world.move_order_count == 0 and world.path.is_empty(), "disabled stop touch does not leak through to map")
    await tap(target_screen)
    verify(world.move_order_count == 1 and not world.path.is_empty(), "squad accepts a new movement order after stop")

    reset_test()
    points = seeded_route()
    world._set_squad_selected(false)
    world.camera.position = world.WORLD_SIZE * 0.5
    world._clamp_camera()
    var old_zoom: Vector2 = world.camera.zoom
    await tap(world.focus_button.get_global_rect().get_center())
    verify(not world.squad_selected and unchanged_route(points) and world.camera.zoom == old_zoom, "focus on unselected squad preserves selection, route and zoom")
    verify(world._squad_screen_rect().has_point(center), "actual focus button brings squad back to viewport center")

func test_hud_crossovers() -> void:
    var controls: Array[Button] = [world.focus_button, world.selection_button, world.stop_button]
    for button in controls:
        reset_test()
        var points: PackedVector2Array = seeded_route()
        var button_point: Vector2 = button.get_global_rect().get_center()
        await route_touch(0, button_point, true)
        await route_drag(0, target_screen, target_screen - button_point)
        await route_touch(0, target_screen, false)
        verify(unchanged_route(points), "touch starting on %s and ending on map cannot issue an order" % button.name)
        verify(world.touch_points.is_empty() and world.ui_touch_ids.is_empty(), "%s drag release cleans up all touch state" % button.name)
        await tap(target_screen)
        verify(world.move_order_count == 1, "fresh map order remains usable after dragging from %s" % button.name)

        reset_test()
        points = seeded_route()
        await route_touch(0, target_screen, true)
        await route_drag(0, target_screen + Vector2(60.0, 0.0), Vector2(60.0, 0.0))
        await route_drag(0, button_point, button_point - target_screen - Vector2(60.0, 0.0))
        await route_touch(0, button_point, false)
        verify(unchanged_route(points), "map pan released on %s preserves route without an accidental button action" % button.name)
        verify(world.squad_selected, "map pan release on %s preserves selection" % button.name)

        reset_test()
        points = seeded_route()
        await route_touch(0, target_screen, true)
        await route_touch(1, button_point, true)
        await route_touch(1, button_point, false)
        await route_touch(0, target_screen, false)
        # An intentionally tapped stop button may clear the route; neither finger
        # may generate a movement order, regardless of that legitimate action.
        verify(world.move_order_count == 0 and world.touch_points.is_empty() and world.ui_touch_ids.is_empty(), "map finger plus %s touch cannot leak a movement order or stranded gesture" % button.name)
        world._set_squad_selected(true)
        await tap(target_screen)
        verify(world.move_order_count == 1, "fresh map order works after map-plus-%s gesture" % button.name)

    reset_test()
    var idle_status: String = world.squad_status.text
    await tap(target_screen)
    verify(world.squad_status.text != idle_status, "HUD status changes when squad receives a route")
    await tap(world.stop_button.get_global_rect().get_center())
    verify(world.squad_status.text == idle_status, "HUD status returns to idle after stopping")

func test_panel_input() -> void:
    reset_test()
    var points: PackedVector2Array = seeded_route()
    var status_point: Vector2 = world.squad_status.get_global_rect().get_center()
    var title_point: Vector2 = world.squad_panel.get_global_rect().position + Vector2(260.0, 30.0)
    verify(world._camera_button_contains(status_point) and world._camera_button_contains(title_point), "nonbutton HUD status and title areas are protected from map input")
    await tap(status_point)
    await tap(title_point)
    verify(unchanged_route(points) and world.squad_selected, "actual status and title touches preserve selection and route without issuing orders")

    await route_touch(0, status_point, true)
    await route_drag(0, target_screen, target_screen - status_point)
    await route_touch(0, target_screen, false)
    verify(unchanged_route(points) and world.touch_points.is_empty() and world.ui_touch_ids.is_empty(), "HUD label drag onto map cannot issue an order or strand gesture state")
    await tap(target_screen)
    verify(world.move_order_count == 1, "fresh map order works after HUD label drag")

    reset_test()
    points = seeded_route()
    await route_touch(0, target_screen, true)
    await route_touch(1, status_point, true)
    await route_touch(1, status_point, false)
    await route_touch(0, target_screen, false)
    verify(unchanged_route(points), "second finger on HUD label suppresses pending map tap")
    await tap(target_screen)
    verify(world.move_order_count == 1, "fresh map order works after map-plus-HUD-label gesture")

func test_physical_movement() -> void:
    reset_test()
    world._request_move(target_screen)
    var start: Vector2 = world.ball_pos
    world._set_squad_selected(false)
    var traversed_solid := false
    var ticks := 0
    while not world.path.is_empty() and ticks < 12000:
        world._process(1.0 / 60.0)
        traversed_solid = traversed_solid or world.nav.is_point_solid(world._cell_from_world(world.ball_pos))
        ticks += 1
    verify(world.ball_pos != start and world.ball_pos.distance_to(target) < 0.1 and not traversed_solid, "deselected squad completes actual path without crossing blocked terrain")
    verify(not world.squad_selected and world.stop_button.disabled, "route completion preserves deselection and keeps stop disabled")

    reset_test()
    world._request_move(target_screen)
    for tick in range(20):
        world._process(1.0 / 60.0)
    var stopped_at: Vector2 = world.ball_pos
    world._stop_squad()
    for tick in range(120):
        world._process(1.0 / 60.0)
    verify(stopped_at != start and world.ball_pos == stopped_at, "stopping mid-route holds the exact current position")

func finish() -> void:
    if failures.is_empty():
        print("PASS_SQUAD_V05 checks=", check_count)
    else:
        push_error("Squad v0.5 failures: %s" % failures)
    if is_instance_valid(world):
        world.free()
    world = null
    quit(0 if failures.is_empty() else 1)
