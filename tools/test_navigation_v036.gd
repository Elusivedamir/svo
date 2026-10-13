extends SceneTree

# Run the real scene, click targets through the real input conversion, and
# advance the actual movement function. Failure terminates APK export in CI.
var world: Node2D
var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("run_checks")

func verify(ok: bool, caption: String) -> void:
    print("PASS " if ok else "FAIL ", caption)
    if not ok:
        failures.append(caption)

func click_world(point: Vector2) -> void:
    var screen: Vector2 = world.get_viewport_rect().size * 0.5 + (point - world.camera.position) * world.camera.zoom
    world._request_move(screen)

func region_grid(rect: Rect2i) -> AStarGrid2D:
    var grid := AStarGrid2D.new()
    grid.region = rect
    grid.cell_size = world.nav_cell
    grid.offset = world.nav_cell * 0.5
    grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
    grid.update()
    for y in range(rect.position.y, rect.end.y):
        for x in range(rect.position.x, rect.end.x):
            var cell := Vector2i(x, y)
            grid.set_point_solid(cell, world.nav.is_point_solid(cell))
    return grid

func run_checks() -> void:
    world = load("res://scenes/world_map.tscn").instantiate()
    world.legacy_regression_mode = true
    root.add_child(world)
    world.set_process(false)
    await process_frame
    if world.nav == null:
        verify(false, "map initialization")
        call_deferred("finish")
        return
    var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/water_regions_v0.3.6.json"))
    var spawn: Vector2 = world.nav.get_point_position(Vector2i(100, 56))
    var rejected := 0
    var blocked := 0
    for y in range(world.nav_size.y):
        for x in range(world.nav_size.x):
            var cell := Vector2i(x, y)
            if not world.nav.is_point_solid(cell):
                continue
            blocked += 1
            world.ball_pos = spawn
            world.path.clear()
            world.blocked_timer = 0.0
            click_world(world.nav.get_point_position(cell))
            if world.path.is_empty() and world.blocked_timer > 0.0:
                rejected += 1
    verify(blocked > 8000 and rejected == blocked, "all %d blocked target cells reject movement" % blocked)
    # These two destinations were reachable over visibly painted water in v0.3.4.
    for cell in [Vector2i(28, 52), Vector2i(395, 19)]:
        world.ball_pos = spawn
        world.path.clear()
        world.blocked_timer = 0.0
        var target: Vector2 = world.nav.get_point_position(cell)
        click_world(target)
        world._process(0.08)
        verify(world._type_at(target) == world.CELL_WATER and world.path.is_empty() and world.blocked_timer > 0.0 and world.ball_pos == spawn, "previously missed visible water %s is blocked" % cell)
    var coordinate_size := Vector2(float(spec.coordinate_size[0]), float(spec.coordinate_size[1]))
    for feature in spec.water_polygons + spec.water_channels:
        var point: Vector2 = Vector2(float(feature.probe[0]), float(feature.probe[1])) / coordinate_size * world.WORLD_SIZE
        verify(world._type_at(point) == world.CELL_WATER, "named water region: %s" % feature.name)
    for probe in spec.dry_probes:
        var cell := Vector2i(int(probe.cell[0]), int(probe.cell[1]))
        world.ball_pos = spawn
        world.path.clear()
        click_world(world.nav.get_point_position(cell))
        var accepted: bool = not world.path.is_empty()
        var ticks := 0
        while not world.path.is_empty() and ticks < 40000:
            world._process(1.0 / 60.0)
            ticks += 1
        verify(accepted and world.ball_pos.distance_to(world.nav.get_point_position(cell)) < 0.1, "dry area reachable: %s" % probe.name)
    for bridge in spec.bridges:
        var a := Vector2i(int(bridge.from[0]), int(bridge.from[1]))
        var b := Vector2i(int(bridge.to[0]), int(bridge.to[1]))
        world.ball_pos = world.nav.get_point_position(a)
        world.path.clear()
        click_world(world.nav.get_point_position(b))
        var accepted: bool = not world.path.is_empty()
        var bridge_steps := 0
        var bad_waypoints := 0
        for waypoint in world.path:
            if world._type_at(waypoint) == world.CELL_BRIDGE:
                bridge_steps += 1
            if world.nav.is_point_solid(world._cell_from_world(waypoint)):
                bad_waypoints += 1
        var ticks := 0
        var bad_movement := 0
        while not world.path.is_empty() and ticks < 40000:
            world._process(1.0 / 60.0)
            if world.nav.is_point_solid(world._cell_from_world(world.ball_pos)):
                bad_movement += 1
            ticks += 1
        verify(accepted and bridge_steps > 0 and bad_waypoints == 0 and bad_movement == 0 and world.ball_pos.distance_to(world.nav.get_point_position(b)) < 0.1, "actual bank-to-bank movement over %s bridge" % bridge.name)
        var region: Array = bridge.local_region
        var grid: AStarGrid2D = region_grid(Rect2i(int(region[0]), int(region[1]), int(region[2]), int(region[3])))
        var open_path: PackedVector2Array = grid.get_point_path(a, b)
        for y in range(grid.region.position.y, grid.region.end.y):
            for x in range(grid.region.position.x, grid.region.end.x):
                var cell := Vector2i(x, y)
                if world._type_at(world.nav.get_point_position(cell)) == world.CELL_BRIDGE:
                    grid.set_point_solid(cell, true)
        verify(not open_path.is_empty() and grid.get_point_path(a, b).is_empty(), "local %s river cannot be crossed after closing its bridge" % bridge.name)
    for dst in [Vector2i(185, 61), Vector2i(310, 56), Vector2i(100, 178), Vector2i(310, 178)]:
        verify(not world.nav.get_point_path(Vector2i(100, 56), dst).is_empty(), "cross-sector route to %s" % dst)
    # User video showed dry NW land that had no path despite solid=false.
    for target_cell in [Vector2i(10, 23), Vector2i(34, 15)]:
        world.ball_pos = spawn
        world.path.clear()
        click_world(world.nav.get_point_position(target_cell))
        var accepted: bool = not world.path.is_empty()
        var ticks := 0
        var bad_movement := 0
        while not world.path.is_empty() and ticks < 40000:
            world._process(1.0 / 60.0)
            if world.nav.is_point_solid(world._cell_from_world(world.ball_pos)):
                bad_movement += 1
            ticks += 1
        verify(accepted and bad_movement == 0 and world.ball_pos.distance_to(world.nav.get_point_position(target_cell)) < 0.1, "dry northwest video regression: reached %s" % target_cell)
    var material: ShaderMaterial = world.terrain.material as ShaderMaterial
    verify(material != null and material.shader != null and material.shader.resource_path == "res://shaders/terrain_clarity.gdshader", "terrain clarity shader is loaded")
    verify(world.terrain.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "terrain uses mipmap filtering")
    verify(world.terrain.texture.get_image().has_mipmaps(), "terrain import actually generates mipmaps")
    if material != null and material.shader != null:
        var uniforms := material.shader.get_shader_uniform_list()
        var names: Array[String] = []
        for uniform in uniforms:
            names.append(String(uniform.name))
        verify(names.has("sharpen_strength") and names.has("detail_limit") and names.has("contrast") and names.has("brightness"), "terrain clarity shader uniforms parse")
    call_deferred("finish")

func finish() -> void:
    if failures.is_empty():
        print("PASS_NAVIGATION_V036")
    else:
        push_error("Navigation v0.3.6 failures: %s" % failures)
    world.free()
    world = null
    quit(0 if failures.is_empty() else 1)
