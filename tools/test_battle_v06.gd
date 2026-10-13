extends SceneTree

# End-to-end player flows through the production map and actual viewport GUI.
# Simulation time is advanced deliberately, independently from CI frame speed.
var world: Node2D
var failures: Array[String] = []
var check_count := 0
var center := Vector2.ZERO
var player_id := -1

func _initialize() -> void:
    root.size = Vector2i(1280, 591)
    call_deferred("run_checks")

func verify(ok: bool, caption: String) -> void:
    check_count += 1
    print("PASS " if ok else "FAIL ", caption)
    if not ok:
        failures.append(caption)

func touch(index: int, point: Vector2, pressed: bool, canceled := false) -> void:
    var event := InputEventScreenTouch.new()
    event.index = index
    event.position = root.get_screen_transform() * point
    event.pressed = pressed
    event.canceled = canceled
    Input.parse_input_event(event)
    await process_frame

func drag(index: int, point: Vector2, relative: Vector2) -> void:
    var event := InputEventScreenDrag.new()
    event.index = index
    event.position = root.get_screen_transform() * point
    event.relative = root.get_screen_transform().basis_xform(relative)
    Input.parse_input_event(event)
    await process_frame

func tap(point: Vector2, index := 0) -> void:
    await touch(index, point, true)
    await touch(index, point, false)

func press(button: Button) -> void:
    await tap(button.get_global_rect().get_center())

func screen(point: Vector2) -> Vector2:
    return center + (point - world.camera.position) * world.camera.zoom

func select_player() -> Dictionary:
    for unit in world.model.units:
        if int(unit.side) == 0:
            player_id = int(unit.id)
            world._select_unit(player_id)
            return unit
    return {}

func all_positions() -> Array:
    var result: Array = []
    for unit in world.model.units:
        result.append(unit.pos)
    return result

func all_paths() -> Array:
    var result: Array = []
    for unit in world.model.units:
        result.append(unit.path.duplicate())
    return result

func advance(seconds: float) -> void:
    var ticks := ceili(seconds / 0.1)
    for tick in range(ticks):
        world._process(minf(0.1, seconds - tick * 0.1))

func nearby_walkable(origin: Vector2, offset := Vector2i(8, 0)) -> Vector2:
    var cell: Vector2i = world._cell_from_world(origin)
    for ring in range(0, 20):
        for dy in range(-ring, ring + 1):
            for dx in range(-ring, ring + 1):
                var candidate: Vector2i = cell + offset + Vector2i(dx, dy)
                if not world._inside(candidate) or world.nav.is_point_solid(candidate):
                    continue
                if not world.nav.get_point_path(cell, candidate).is_empty():
                    return world.nav.get_point_position(candidate)
    return origin

func update_hud() -> void:
    world._update_battle_hud()

func run_checks() -> void:
    world = load("res://tools/battle_v06_probe.gd").new()
    root.add_child(world)
    world.set_process(false)
    await process_frame
    center = world.get_viewport_rect().size * 0.5
    if world.nav == null or world.camera == null or world.model == null:
        verify(false, "production battle scene initializes")
        finish()
        return
    verify(not world.legacy_regression_mode, "normal production scene uses the complete battle controller")
    await test_preparation()
    await test_camera_and_interface()
    await test_start_and_pause()
    await test_movement_and_stop()
    test_actual_bridge_movement()
    await test_drone_and_capture()
    test_live_observation()
    test_capture_and_end()
    call_deferred("finish")

func test_preparation() -> void:
    verify(world.model.phase == "prepare", "scene starts in untimed preparation")
    var own_bunkers := 0
    var enemy_bunkers := 0
    var own_posts := 0
    for site in world.model.structures:
        if site.kind == "bunker":
            own_bunkers += 1 if int(site.side) == 0 else 0
            enemy_bunkers += 1 if int(site.side) == 1 else 0
        elif site.kind == "post" and int(site.side) == 0:
            own_posts += 1
    verify(own_bunkers == 4 and enemy_bunkers == 4 and own_posts == 1, "setup creates four bunkers per side and the player's observation post")
    var own_units := 0
    var enemy_units := 0
    var full_squads := true
    var legal_spawns := true
    for unit in world.model.units:
        own_units += 1 if int(unit.side) == 0 else 0
        enemy_units += 1 if int(unit.side) == 1 else 0
        full_squads = full_squads and world.model.alive_count(unit) == 6
        legal_spawns = legal_spawns and not world.nav.is_point_solid(world._cell_from_world(unit.pos))
    verify(own_units == 4 and enemy_units == 4 and full_squads, "both sides start with four six-person infantry groups")
    verify(legal_spawns, "all generated positions are on legal terrain")
    verify(is_equal_approx(world.model.percent(0), 50.0) and is_equal_approx(world.model.percent(1), 50.0), "territory starts at equal 50/50 ownership")
    verify(world.unit_buttons.size() == 4 and world.drone_button != null and world.post_button != null, "HUD exposes all four groups, drone and post")
    verify(world.weather_option.item_count == 3 and world.time_option.item_count == 3, "preparation exposes three weather and three daylight conditions")
    var hidden := true
    for unit in world.model.units:
        if int(unit.side) == 1:
            hidden = hidden and not sees(unit.pos)
    verify(hidden, "enemy positions are hidden during initial preparation")
    var saved: Array = all_positions()
    world._process(3600.0)
    verify(world.model.phase == "prepare" and all_positions() == saved, "one simulated hour of preparation never starts or moves the bot")
    var unit: Dictionary = select_player()
    var destination := nearby_walkable(unit.pos)
    world.camera.position = unit.pos
    world._clamp_camera()
    world.map_tap_count = 0
    await tap(screen(destination))
    verify(unit.pos.distance_to(destination) < 0.1 and unit.path.is_empty(), "preparation map tap relocates the selected position without starting movement")
    var old_position: Vector2 = unit.pos
    var forbidden := Vector2(world.WORLD_SIZE.x * 0.85, world.WORLD_SIZE.y * 0.5)
    world._handle_map_tap(screen(forbidden))
    verify(unit.pos == old_position, "preparation cannot relocate a player position onto the enemy half")
    var post: Dictionary = {}
    for site in world.model.structures:
        if site.kind == "post" and int(site.side) == 0:
            post = site
            break
    var post_destination := nearby_walkable(post.pos)
    world.camera.position = post.pos
    world._clamp_camera()
    await press(world.post_button)
    await tap(screen(post_destination))
    verify(post.pos.distance_to(post_destination) < 0.1 and world.model.drone.pos.distance_to(post.pos) < 0.1, "preparation post selection relocates the observation post and its ready drone together")
    var all_arranged := true
    for index in range(world.unit_buttons.size()):
        await press(world.unit_buttons[index])
        var member: Dictionary = world.model.unit_by_id(world.selected_unit)
        var new_position := nearby_walkable(member.pos, Vector2i(6, 0))
        world.camera.position = member.pos
        world._clamp_camera()
        await tap(screen(new_position))
        all_arranged = all_arranged and member.pos.distance_to(new_position) < 0.1
    verify(all_arranged and world.model.phase == "prepare", "player can independently adjust all four infantry positions before starting")

func test_camera_and_interface() -> void:
    var bounds: Rect2 = world.get_viewport_rect()
    var buttons: Array = world.unit_buttons.duplicate()
    buttons.append_array([world.drone_button, world.post_button, world.start_button, world.pause_button, world.focus_button])
    for mode in world.mode_buttons.values():
        buttons.append(mode)
    var fits := true
    var minimum_touch := true
    for button in buttons:
        if not button.visible:
            continue
        fits = fits and bounds.encloses(button.get_global_rect())
        minimum_touch = minimum_touch and button.size.y >= 56.0
    verify(fits and minimum_touch, "visible interactive battle controls fit the viewport with usable touch targets")
    var unit: Dictionary = select_player()
    var before: Array = all_positions()
    world.map_tap_count = 0
    await press(world.unit_buttons[1])
    verify(world.selected_unit != player_id and world.map_tap_count == 0 and all_positions() == before, "actual group button changes selection without relocating a position")
    await press(world.drone_button)
    verify(world.selected_drone and world.map_tap_count == 0, "actual drone button selects the drone without leaking a map tap")
    await press(world.post_button)
    verify(world.selected_post and world.map_tap_count == 0, "actual observation-post button selects the post without a map order")
    select_player()
    var zoom_before: Vector2 = world.camera.zoom
    var left := center - Vector2(140.0, 0.0)
    var right := center + Vector2(140.0, 0.0)
    await touch(0, left, true)
    await touch(3, right, true)
    await drag(0, left - Vector2(70.0, 0.0), Vector2(-70.0, 0.0))
    await touch(3, right, false)
    await touch(0, left - Vector2(70.0, 0.0), false)
    verify(world.camera.zoom.x > zoom_before.x and world.map_tap_count == 0 and all_positions() == before, "actual two-finger pinch zooms without repositioning soldiers or post")
    world.camera.position = world.WORLD_SIZE * 0.5
    world._clamp_camera()
    var zoom_focus: Vector2 = world.camera.zoom
    await press(world.focus_button)
    verify(screen(unit.pos).distance_to(center) < 0.1 and world.camera.zoom == zoom_focus and world.map_tap_count == 0, "actual focus button centers selected group and preserves zoom")

func test_start_and_pause() -> void:
    world.weather_option.select(1)
    world.weather_option.item_selected.emit(1)
    world.time_option.select(1)
    world.time_option.item_selected.emit(1)
    update_hud()
    var old_positions: Array = all_positions()
    world.map_tap_count = 0
    await press(world.start_button)
    verify(world.model.phase == "battle" and world.map_tap_count == 0, "actual start button begins battle without a movement order")
    verify(world.weather_option.disabled and world.time_option.disabled, "weather and daylight selection lock after battle starts")
    verify(all_positions() == old_positions, "start button does not teleport any group")
    verify(world.model.visibility.weather == "rain" and world.model.visibility.time_of_day == "dusk", "selected preparation conditions reach the actual observation system")
    world.model.ai_enabled = false
    world.model.combat_enabled = false
    await press(world.pause_button)
    verify(world.model.paused, "actual pause button suspends the battle")
    old_positions = all_positions()
    advance(5.0)
    verify(all_positions() == old_positions and world.model.paused, "paused production ticks cannot move either side")
    await press(world.pause_button)
    verify(not world.model.paused, "actual pause button resumes the battle")
    world._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
    var saved_elapsed: float = world.model.elapsed
    advance(5.0)
    verify(world.model.paused and world.model.elapsed == saved_elapsed, "backgrounding the app automatically freezes the battle")
    await press(world.pause_button)
    verify(not world.model.paused, "player can resume after returning to the app")

func test_movement_and_stop() -> void:
    var unit: Dictionary = select_player()
    world.camera.position = unit.pos
    world._clamp_camera()
    if world.mode_buttons.has("move"):
        await press(world.mode_buttons.move)
    var destination := nearby_walkable(unit.pos, Vector2i(16, 0))
    var start: Vector2 = unit.pos
    world.map_tap_count = 0
    await tap(screen(destination), 2)
    verify(world.map_tap_count == 1 and not unit.path.is_empty(), "actual map tap gives selected group one navigation route")
    advance(0.5)
    verify(unit.pos.distance_to(start) > 0.1 and unit.pos.distance_to(destination) > 0.1, "group advances over time instead of teleporting to the destination")
    if world.mode_buttons.has("stop"):
        await press(world.mode_buttons.stop)
    else:
        world.model.order_stop(player_id)
    var stopped: Vector2 = unit.pos
    verify(unit.path.is_empty(), "stop clears the selected group's active movement route")
    advance(1.0)
    verify(unit.pos == stopped, "stopped group remains stationary on later production ticks")
    if world.mode_buttons.has("move"):
        await press(world.mode_buttons.move)
    await tap(screen(destination))
    var all_legal := true
    for tick in range(500):
        world._process(0.1)
        all_legal = all_legal and not world.nav.is_point_solid(world._cell_from_world(unit.pos))
        if unit.path.is_empty():
            break
    verify(all_legal and unit.pos.distance_to(destination) < 0.1, "selected group follows real navigation to its destination without crossing blocked cells")

func sees(point: Vector2) -> bool:
    return world.model.visibility.is_visible(point, 0, world.model.units, world.model.structures, world.model.drone, world.model.phase)

func test_actual_bridge_movement() -> void:
    var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/water_regions_v0.3.6.json"))
    var extra: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/bridge_corridors_v0.5.1.json"))
    var bridges: Array = spec.bridges.duplicate()
    bridges.append_array(extra.bridges)
    var group: Dictionary = world.model.unit_by_id(player_id)
    for bridge in bridges:
        var from_cell := Vector2i(int(bridge["from"][0]), int(bridge["from"][1]))
        var to_cell := Vector2i(int(bridge["to"][0]), int(bridge["to"][1]))
        group.pos = world.nav.get_point_position(from_cell)
        var target: Vector2 = world.nav.get_point_position(to_cell)
        var accepted: bool = world.model.order_move(player_id, target)
        var bridge_waypoint := false
        for waypoint in group.path:
            bridge_waypoint = bridge_waypoint or world._type_at(waypoint) == world.CELL_BRIDGE
        verify(accepted and bridge_waypoint, "new battle model routes infantry over %s bridge" % bridge.name)
        var safe := true
        var ticks := 0
        while not group.path.is_empty() and ticks < 1000:
            world._process(0.05)
            safe = safe and not world.nav.is_point_solid(world._cell_from_world(group.pos))
            for feet in world.view.soldier_positions(group):
                safe = safe and not world.nav.is_point_solid(world._cell_from_world(feet))
            ticks += 1
        verify(safe and group.pos.distance_to(target) < 0.1, "all displayed infantry and group anchor stay on legal terrain while crossing %s" % bridge.name)

func test_drone_and_capture() -> void:
    # Move observers out of this test area without revealing it through ownership.
    for unit in world.model.units:
        unit.pos = Vector2(100.0, 100.0) if int(unit.side) == 0 else Vector2(12600.0, 7000.0)
        unit.path.clear()
    var post: Dictionary = {}
    for site in world.model.structures:
        if site.kind == "post" and int(site.side) == 0:
            post = site
            break
    post.pos = Vector2(6100.0, 5400.0)
    world.model.drone.pos = post.pos
    world.model.drone.state = "ready"
    world.model.drone.charge = 100.0
    var destination := Vector2(7500.0, 5400.0)
    world.camera.position = destination
    world._clamp_camera()
    var ownership: float = world.model.percent(0)
    await press(world.drone_button)
    world.map_tap_count = 0
    await tap(screen(destination))
    verify(world.selected_drone and world.model.drone.state == "flying" and world.map_tap_count == 1, "actual selected-drone map tap dispatches the drone to its assigned point")
    verify(not sees(destination), "assigning a remote drone point does not reveal it before arrival")
    var origin: Vector2 = world.model.drone.pos
    advance(0.2)
    verify(world.model.drone.pos.distance_to(origin) > 0.1 and world.model.drone.pos.distance_to(destination) > 0.1 and not sees(destination), "drone travels over time while its destination stays hidden")
    for tick in range(1000):
        world._process(0.1)
        if world.model.drone.state == "observing":
            break
    verify(world.model.drone.state == "observing" and world.model.drone.pos.distance_to(destination) < 0.1 and sees(destination), "only the arrived observing drone opens current fog at the assigned point")
    verify(is_equal_approx(world.model.percent(0), ownership), "drone reconnaissance does not claim territory")
    world.model.return_drone()
    verify(not sees(destination), "ordering drone return immediately restores fog where no soldiers remain")
    for tick in range(1000):
        world._process(0.1)
        if world.model.drone.state == "ready":
            break
    verify(world.model.drone.state == "ready" and world.model.drone.pos.distance_to(post.pos) < 0.1, "returning drone physically reaches its observation post")

    var group: Dictionary = select_player()
    var target_sector: Dictionary = {}
    for sector in world.model.sectors:
        if int(sector.owner) == 1:
            target_sector = sector
            break
    var target: Vector2 = target_sector.pos
    group.pos = target
    group.path.clear()
    world.camera.position = target
    world._clamp_camera()
    if world.mode_buttons.has("capture"):
        await press(world.mode_buttons.capture)
    var before_supply: float = float(world.model.supplies[0])
    var before_percent: float = world.model.percent(0)
    await tap(screen(target + Vector2(180.0, 0.0)))
    verify(group.order == "capture", "actual capture mode and map tap issue a position-capture order")
    advance(10.0)
    verify(int(target_sector.owner) == 1 and is_equal_approx(world.model.percent(0), before_percent), "passing through or briefly occupying a position does not immediately capture it")
    advance(13.0)
    verify(int(target_sector.owner) == 0 and world.model.percent(0) > before_percent, "holding the uncontested position changes its ownership and territory percentage")
    update_hud()
    verify("62.5" in world.territory_label.text and "37.5" in world.territory_label.text, "territory HUD preserves fractional shares instead of rounding both sides to 101 percent")
    verify(is_equal_approx(float(world.model.supplies[0]), before_supply + 100.0), "first capture of an enemy bunker grants the promised supplies")
    var site_changed := false
    for site in world.model.structures:
        if site.kind == "bunker" and int(site.sector) == int(target_sector.id):
            site_changed = int(site.side) == 0
    verify(site_changed, "captured bunker changes side with its territory")
    var reward: float = float(world.model.supplies[0])
    advance(30.0)
    verify(is_equal_approx(float(world.model.supplies[0]), reward), "remaining on a captured bunker does not repeatedly produce supplies")
    group.pos = Vector2(100.0, 100.0)
    verify(int(target_sector.owner) == 0 and not sees(target), "empty captured territory stays owned while its observation disappears")

func test_live_observation() -> void:
    # Detailed visibility/drone model regressions run separately; this scene
    # check verifies the production controller uses current model observation.
    verify(world.view != null, "scene owns the visible-soldier and fog renderer")
    var enemy: Dictionary = {}
    for unit in world.model.units:
        if int(unit.side) == 1:
            enemy = unit
            break
    if enemy.is_empty():
        verify(false, "enemy group exists for live observation check")
        return
    var observer: Dictionary = world.model.unit_by_id(player_id)
    var observer_position: Vector2 = observer.pos
    enemy.pos = world.model.sectors[2].pos
    observer.pos = enemy.pos
    verify(world.model.visibility.is_visible(enemy.pos, 0, world.model.units, world.model.structures, world.model.drone, world.model.phase), "nearby living group supplies current enemy observation")
    observer.pos = Vector2(1.0, 1.0)
    for unit in world.model.units:
        if int(unit.side) == 0 and int(unit.id) != player_id:
            unit.pos = Vector2(1.0, 1.0)
    verify(not world.model.visibility.is_visible(enemy.pos, 0, world.model.units, world.model.structures, world.model.drone, world.model.phase), "previously seen enemy becomes hidden after all player observers leave")
    observer.pos = observer_position

func test_capture_and_end() -> void:
    # A deterministic end-state fixture checks that the full controller updates
    # territory and disables commands when the simulation reports an outcome.
    var owns_sum: float = world.model.percent(0) + world.model.percent(1)
    verify(is_equal_approx(owns_sum, 100.0), "territory ownership remains normalized during the match")
    for unit in world.model.units:
        if int(unit.side) == 1:
            for index in range(unit.hp.size()):
                unit.hp[index] = 0.0
    advance(0.1)
    update_hud()
    verify(world.model.phase == "ended", "eliminating all opposing groups ends the running match")
    var saved: Array = all_positions()
    var paths: Array = all_paths()
    world._handle_map_tap(screen(nearby_walkable(world.model.unit_by_id(player_id).pos)))
    advance(1.0)
    verify(all_positions() == saved and all_paths() == paths, "completed match cannot accept new movement orders or continue simulation")
    verify(world.start_button.visible and world.start_button.text == "ЗАНОВО", "completed battle offers an actual replay control")
    world._start_battle()
    verify(world.model.phase == "prepare" and world.model.elapsed == 0.0 and world.model.ai_enabled and world.model.combat_enabled, "replay resets preparation and re-enables the normal bot and combat")
    verify(world.model.percent(0) == 50.0 and world.model.percent(1) == 50.0 and world.model.alive_count(world.model.units[0]) == 6, "replay restores starting control and the full infantry roster")

func finish() -> void:
    if failures.is_empty():
        print("PASS_BATTLE_V06 checks=", check_count)
        quit(0)
    else:
        push_error("FAIL_BATTLE_V06 checks=%d failures=%s" % [check_count, str(failures)])
        quit(1)
