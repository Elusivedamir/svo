extends SceneTree

# Run with --headless --path PROJECT --script res://tools/test_camera_v04.gd.
# Tests feed the real touch handler and count calls to real movement/pathfinding.
var world: Node2D
var failures: Array[String] = []
var check_count: int = 0
var center: Vector2
var viewport_size: Vector2
var baseline_zoom: float

func _initialize() -> void:
    call_deferred("run_checks")

func verify(ok: bool, caption: String) -> void:
    check_count += 1
    print("PASS " if ok else "FAIL ", caption)
    if not ok:
        failures.append(caption)

func touch(index: int, point: Vector2, pressed: bool, canceled: bool = false) -> void:
    var event: InputEventScreenTouch = InputEventScreenTouch.new()
    event.index = index
    event.position = point
    event.pressed = pressed
    event.canceled = canceled
    world._unhandled_input(event)

func drag(index: int, point: Vector2, relative: Vector2 = Vector2.ZERO) -> void:
    var event: InputEventScreenDrag = InputEventScreenDrag.new()
    event.index = index
    event.position = point
    event.relative = relative
    world._unhandled_input(event)

func route_touch(index: int, point: Vector2, pressed: bool) -> void:
    var event: InputEventScreenTouch = InputEventScreenTouch.new()
    event.index = index
    event.position = root.get_screen_transform() * point
    event.pressed = pressed
    Input.parse_input_event(event)
    await process_frame

func route_drag(index: int, point: Vector2, relative: Vector2) -> void:
    var event: InputEventScreenDrag = InputEventScreenDrag.new()
    event.index = index
    event.position = root.get_screen_transform() * point
    event.relative = root.get_screen_transform().basis_xform(relative)
    Input.parse_input_event(event)
    await process_frame

func reset_test() -> void:
    # Canceled releases clean up previous scenarios without issuing orders.
    for index in range(8):
        touch(index, center, false, true)
    world.returning = false
    world.move_order_count = 0
    world.ball_pos = world.nav.get_point_position(Vector2i(100, 56))
    world.path.clear()
    world.path_next = 0
    world.blocked_timer = 0.0
    world.camera.zoom = Vector2.ONE * baseline_zoom
    world.camera.position = world.WORLD_SIZE * 0.5
    world._clamp_camera()

func seeded_path() -> PackedVector2Array:
    var points: PackedVector2Array = world.nav.get_point_path(Vector2i(100, 56), Vector2i(185, 61))
    world.path = points.duplicate()
    world.path_next = 3
    return points

func unchanged_route(points: PackedVector2Array) -> bool:
    return world.move_order_count == 0 and world.path == points and world.path_next == 3

func pinch_points(separation: float) -> Array[Vector2]:
    return [center - Vector2(separation * 0.5, 0.0), center + Vector2(separation * 0.5, 0.0)]

func run_checks() -> void:
    world = load("res://tools/camera_v04_probe.gd").new()
    root.add_child(world)
    world.set_process(false)
    await process_frame
    viewport_size = world.get_viewport_rect().size
    center = viewport_size * 0.5
    if world.nav == null or world.camera == null:
        verify(false, "real map and camera initialize")
        finish()
        return
    baseline_zoom = (world.camera_min_zoom + world.camera_max_zoom) * 0.5
    verify(viewport_size.x > 100.0 and viewport_size.y > 100.0, "test viewport has usable touch coordinates")
    test_taps()
    test_pan()
    test_pinch_zoom()
    test_pinch_bounds()
    test_release_orders()
    test_cancel_and_extra_fingers()
    test_focus()
    test_wheel()
    test_interrupt_cleanup()
    await test_gui_routing()
    await test_menu_cleanup()
    call_deferred("finish")

func test_taps() -> void:
    reset_test()
    world.camera.position = world.ball_pos
    world._clamp_camera()
    touch(0, center, true)
    touch(0, center, false)
    verify(world.move_order_count == 1 and not world.path.is_empty(), "single tap issues exactly one real movement order")

    reset_test()
    world.camera.position = world.ball_pos
    world._clamp_camera()
    touch(4, center, true)
    touch(4, center, false)
    verify(world.move_order_count == 1 and not world.path.is_empty(), "single touch works with a nonzero finger index")

    reset_test()
    world.camera.position = world.ball_pos
    world._clamp_camera()
    touch(0, center, true)
    drag(0, center + Vector2(3.0, 2.0), Vector2(3.0, 2.0))
    touch(0, center + Vector2(3.0, 2.0), false)
    verify(world.move_order_count == 1, "small finger jitter remains a single tap")

func test_pan() -> void:
    reset_test()
    var points: PackedVector2Array = seeded_path()
    var original: Vector2 = world.camera.position
    var shift: Vector2 = Vector2(80.0, 50.0)
    touch(0, center, true)
    drag(0, center + shift, shift)
    touch(0, center + shift, false)
    verify(unchanged_route(points), "one-finger pan preserves the active route and issues no order")
    verify(world.camera.position.distance_to(original - shift / baseline_zoom) < 0.1, "one-finger pan moves camera by screen distance divided by zoom")

    reset_test()
    points = seeded_path()
    touch(0, center, true)
    drag(0, center + shift, shift)
    drag(0, center, -shift)
    touch(0, center, false)
    verify(unchanged_route(points), "drag out and back never becomes a movement tap")

func test_pinch_zoom() -> void:
    reset_test()
    var points: PackedVector2Array = seeded_path()
    var initial_zoom: float = world.camera_max_zoom * 0.45
    world.camera.zoom = Vector2.ONE * initial_zoom
    var start: Array[Vector2] = pinch_points(140.0)
    var end: Array[Vector2] = pinch_points(280.0)
    var anchor: Vector2 = world._screen_to_world(center)
    touch(0, start[0], true)
    touch(1, start[1], true)
    drag(0, end[0], end[0] - start[0])
    drag(1, end[1], end[1] - start[1])
    verify(absf(world.camera.zoom.x - initial_zoom * 2.0) < 0.001, "spreading two fingers doubles zoom from distance ratio")
    verify(world._screen_to_world(center).distance_to(anchor) < 0.1, "pinch keeps the centroid anchored to the same map point")
    touch(1, end[1], false)
    touch(0, end[0], false)
    verify(unchanged_route(points), "pinch zoom never changes the active movement route")

    reset_test()
    initial_zoom = world.camera_min_zoom * 2.5
    world.camera.zoom = Vector2.ONE * initial_zoom
    start = pinch_points(280.0)
    end = pinch_points(140.0)
    touch(0, start[0], true)
    touch(1, start[1], true)
    drag(0, end[0], end[0] - start[0])
    drag(1, end[1], end[1] - start[1])
    verify(absf(world.camera.zoom.x - initial_zoom * 0.5) < 0.001, "closing two fingers halves zoom from distance ratio")
    touch(0, end[0], false)
    touch(1, end[1], false)
    verify(world.move_order_count == 0, "zooming out issues no movement order")

    reset_test()
    start = pinch_points(160.0)
    var moved_first: Vector2 = start[0] + Vector2(-60.0, 50.0)
    touch(0, start[0], true)
    touch(1, start[1], true)
    anchor = world._screen_to_world(center)
    drag(0, moved_first, moved_first - start[0])
    var new_centroid: Vector2 = (moved_first + start[1]) * 0.5
    verify(world._screen_to_world(new_centroid).distance_to(anchor) < 0.1, "moving pinch centroid pans while preserving its map anchor")
    touch(0, moved_first, false)
    touch(1, start[1], false)

func test_pinch_bounds() -> void:
    reset_test()
    var start: Array[Vector2] = pinch_points(24.0)
    var wide: Array[Vector2] = pinch_points(viewport_size.x * 0.8)
    touch(0, start[0], true)
    touch(1, start[1], true)
    drag(0, wide[0], wide[0] - start[0])
    drag(1, wide[1], wide[1] - start[1])
    verify(absf(world.camera.zoom.x - world.camera_max_zoom) < 0.01, "pinch clamps zoom at the maximum")
    touch(0, wide[0], false)
    touch(1, wide[1], false)

    reset_test()
    touch(0, wide[0], true)
    touch(1, wide[1], true)
    drag(0, start[0], start[0] - wide[0])
    drag(1, start[1], start[1] - wide[1])
    verify(absf(world.camera.zoom.x - world.camera_min_zoom) < 0.01, "pinch clamps zoom at the minimum")
    touch(0, start[0], false)
    touch(1, start[1], false)
    verify(world.move_order_count == 0, "touch releases at zoom bounds issue no order")

func test_release_orders() -> void:
    for reverse_down in [false, true]:
        for reverse_up in [false, true]:
            reset_test()
            var points: PackedVector2Array = seeded_path()
            var positions: Array[Vector2] = pinch_points(180.0)
            var first: int = 3 if reverse_down else 0
            var second: int = 0 if reverse_down else 3
            touch(first, positions[0], true)
            touch(second, positions[1], true)
            var released: int = first if reverse_up else second
            var remaining: int = second if reverse_up else first
            var release_point: Vector2 = positions[0] if reverse_up else positions[1]
            var remain_point: Vector2 = positions[1] if reverse_up else positions[0]
            touch(released, release_point, false)
            drag(remaining, remain_point + Vector2(70.0, -30.0), Vector2(70.0, -30.0))
            touch(remaining, remain_point + Vector2(70.0, -30.0), false)
            verify(unchanged_route(points), "pinch release order down=%s up=%s and remaining finger drag issue no order" % [reverse_down, reverse_up])
            world.camera.position = world.ball_pos
            world._clamp_camera()
            touch(1, center, true)
            touch(1, center, false)
            verify(world.move_order_count == 1, "fresh tap works after full pinch release down=%s up=%s" % [reverse_down, reverse_up])

func test_cancel_and_extra_fingers() -> void:
    reset_test()
    var points: PackedVector2Array = seeded_path()
    touch(0, center, true)
    touch(0, center, false, true)
    verify(unchanged_route(points), "canceled single touch never issues a movement order")

    reset_test()
    points = seeded_path()
    var positions: Array[Vector2] = pinch_points(160.0)
    touch(0, positions[0], true)
    touch(1, positions[1], true)
    touch(0, positions[0], false, true)
    touch(1, positions[1], false)
    verify(unchanged_route(points), "canceling one pinch finger suppresses the remaining release")

    reset_test()
    points = seeded_path()
    touch(0, positions[0], true)
    touch(1, positions[1], true)
    touch(2, center + Vector2(0.0, 60.0), true)
    drag(2, center + Vector2(70.0, 90.0), Vector2(70.0, 30.0))
    touch(0, positions[0], false)
    drag(1, positions[1] + Vector2(20.0, 10.0), Vector2(20.0, 10.0))
    touch(1, positions[1] + Vector2(20.0, 10.0), false)
    touch(2, center + Vector2(70.0, 90.0), false)
    verify(unchanged_route(points), "third finger and reordered releases cannot issue a movement order")
    verify(world.camera.zoom.x >= world.camera_min_zoom and world.camera.zoom.x <= world.camera_max_zoom and world.camera.position.is_finite(), "third finger leaves camera finite and zoom within bounds")
    world.camera.position = world.ball_pos
    world._clamp_camera()
    touch(0, center, true)
    touch(0, center, false)
    verify(world.move_order_count == 1, "fresh tap works after three-finger gesture")

func test_focus() -> void:
    reset_test()
    var points: PackedVector2Array = seeded_path()
    var marker: Vector2 = world.ball_pos
    var zoom: Vector2 = world.camera.zoom
    world._focus_marker()
    var half_view: Vector2 = viewport_size * 0.5 / zoom
    var expected: Vector2 = Vector2(
        clampf(marker.x, minf(half_view.x, world.WORLD_SIZE.x * 0.5), maxf(world.WORLD_SIZE.x - half_view.x, world.WORLD_SIZE.x * 0.5)),
        clampf(marker.y, minf(half_view.y, world.WORLD_SIZE.y * 0.5), maxf(world.WORLD_SIZE.y - half_view.y, world.WORLD_SIZE.y * 0.5))
    )
    verify(world.camera.position.distance_to(expected) < 0.1, "camera focus returns to marker while respecting map edges")
    verify(unchanged_route(points) and world.ball_pos == marker and world.camera.zoom == zoom, "camera focus preserves movement route, marker position and zoom")

    reset_test()
    points = seeded_path()
    var button: Button = world.focus_button as Button
    verify(button != null and button.name == "FocusMarker" and button.mouse_filter == Control.MOUSE_FILTER_STOP and button.size.y >= 112.0, "visible focus button has a mobile touch target and consumes GUI input")
    if button != null:
        button.emit_signal("pressed")
        verify(world.camera.position.distance_to(expected) < 0.1 and unchanged_route(points), "focus button signal centers camera without changing the route")

    reset_test()
    points = seeded_path()
    touch(0, center, true)
    world._focus_marker()
    touch(0, center, false)
    verify(unchanged_route(points), "focus during active touch cancels that touch without issuing an order")

func test_wheel() -> void:
    reset_test()
    var point: Vector2 = center + Vector2(90.0, -60.0)
    var anchor: Vector2 = world._screen_to_world(point)
    var event: InputEventMouseButton = InputEventMouseButton.new()
    event.position = point
    event.button_index = MOUSE_BUTTON_WHEEL_UP
    event.pressed = true
    world._unhandled_input(event)
    verify(world.camera.zoom.x > baseline_zoom and world._screen_to_world(point).distance_to(anchor) < 0.1, "desktop wheel zoom keeps cursor map point anchored")
    verify(world.move_order_count == 0, "desktop wheel zoom issues no movement order")

func test_interrupt_cleanup() -> void:
    reset_test()
    var points: PackedVector2Array = seeded_path()
    touch(0, center, true)
    world._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
    touch(0, center, false)
    verify(unchanged_route(points), "app focus loss cancels active touch without a movement order")
    touch(0, center, true)
    touch(0, center, false)
    verify(world.move_order_count == 1, "fresh tap works after app focus loss cleanup")

    reset_test()
    points = seeded_path()
    var positions: Array[Vector2] = pinch_points(160.0)
    touch(0, positions[0], true)
    touch(1, positions[1], true)
    world._resize_camera()
    touch(1, positions[1], false)
    touch(0, positions[0], false)
    verify(unchanged_route(points), "viewport resize cancels active pinch without a movement order")
    verify(world.camera.zoom.x >= world.camera_min_zoom and world.camera.zoom.x <= world.camera_max_zoom, "viewport resize leaves camera zoom within its recomputed bounds")

func test_gui_routing() -> void:
    reset_test()
    var button: Button = world.focus_button as Button
    if button == null:
        verify(false, "focus button exists for real GUI routing checks")
        return
    await process_frame
    var button_point: Vector2 = button.get_global_rect().get_center()

    world.camera.position = world.ball_pos
    world._clamp_camera()
    await route_touch(0, center, true)
    await route_touch(0, center, false)
    verify(world.move_order_count == 1, "actual viewport routing delivers one map tap without emulated mouse duplication")

    reset_test()
    var points: PackedVector2Array = seeded_path()
    await route_touch(0, button_point, true)
    await route_touch(0, button_point, false)
    verify(unchanged_route(points), "actual focus-button touch cannot issue a world movement order")
    verify(world.camera.position.distance_to(world.WORLD_SIZE * 0.5) > 100.0, "actual focus-button touch invokes camera focus")

    reset_test()
    points = seeded_path()
    await route_touch(0, center, true)
    await route_drag(0, center + Vector2(70.0, 0.0), Vector2(70.0, 0.0))
    await route_drag(0, button_point, button_point - center - Vector2(70.0, 0.0))
    await route_touch(0, button_point, false)
    verify(unchanged_route(points), "map drag ending over focus button never issues a movement order")
    await route_touch(0, center, true)
    await route_touch(0, center, false)
    verify(world.move_order_count == 1, "map drag release over button leaves no stranded touch state")

    reset_test()
    points = seeded_path()
    await route_touch(0, center, true)
    await route_touch(1, button_point, true)
    await route_touch(1, button_point, false)
    await route_touch(0, center, false)
    verify(unchanged_route(points), "second finger on focus button suppresses original map tap")
    await route_touch(0, center, true)
    await route_touch(0, center, false)
    verify(world.move_order_count == 1, "map-plus-button gesture leaves fresh map taps usable")

    reset_test()
    points = seeded_path()
    var positions: Array[Vector2] = pinch_points(160.0)
    await route_touch(0, positions[0], true)
    await route_touch(1, positions[1], true)
    await route_drag(0, button_point, button_point - positions[0])
    await route_touch(0, button_point, false)
    await route_touch(1, positions[1], false)
    verify(unchanged_route(points), "pinch finger crossing focus button cannot issue a movement order")
    await route_touch(0, center, true)
    await route_touch(0, center, false)
    verify(world.move_order_count == 1, "pinch release over button leaves fresh map taps usable")

func test_menu_cleanup() -> void:
    reset_test()
    var points: PackedVector2Array = seeded_path()
    var positions: Array[Vector2] = pinch_points(180.0)
    touch(0, positions[0], true)
    touch(1, positions[1], true)
    var event: InputEventAction = InputEventAction.new()
    event.action = "ui_cancel"
    event.pressed = true
    world._unhandled_input(event)
    await process_frame
    verify(world.returning and world.menu_open_count == 1, "Back requests menu once while a gesture is active")
    touch(0, positions[0], false)
    touch(1, positions[1], false)
    verify(unchanged_route(points), "touch releases after Back cannot issue movement orders")
    world.returning = false
    world.camera.position = world.ball_pos
    world._clamp_camera()
    touch(0, center, true)
    touch(0, center, false)
    verify(world.move_order_count == 1, "Back clears gesture state for later fresh input")

func finish() -> void:
    if failures.is_empty():
        print("PASS_CAMERA_V04 checks=", check_count)
    else:
        push_error("Camera v0.4 failures: %s" % failures)
    if is_instance_valid(world):
        world.free()
    world = null
    quit(0 if failures.is_empty() else 1)
