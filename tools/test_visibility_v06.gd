extends SceneTree

const Visibility = preload("res://scripts/battle_visibility.gd")
var visibility: RefCounted
var grid: AStarGrid2D
var kinds := PackedByteArray()
var checks := 0
var failures: Array[String] = []
var unit: Dictionary
var structures: Array
var drone: Dictionary

func _initialize() -> void:
    call_deferred("run_checks")

func verify(ok: bool, caption: String) -> void:
    checks += 1
    print("PASS " if ok else "FAIL ", caption)
    if not ok:
        failures.append(caption)

func visible(point: Vector2, units: Array, sites: Array = [], aircraft: Dictionary = {}, phase: String = "battle", side: int = 0) -> bool:
    return visibility.is_visible(point, side, units, sites, aircraft, phase)

func fog_alpha(image: Image, point: Vector2) -> float:
    var pixel := Vector2i(point / Vector2(4000.0, 2400.0) * Vector2(image.get_size()))
    return image.get_pixelv(pixel).a

func reset_terrain() -> void:
    kinds.fill(0)
    visibility.setup(grid, kinds, Vector2(4000.0, 2400.0), {})

func run_checks() -> void:
    grid = AStarGrid2D.new()
    grid.region = Rect2i(0, 0, 80, 48)
    grid.cell_size = Vector2(50.0, 50.0)
    grid.offset = Vector2(25.0, 25.0)
    grid.update()
    kinds.resize(80 * 48)
    visibility = Visibility.new()
    reset_terrain()
    unit = {"id": 0, "side": 0, "pos": Vector2(1000.0, 1200.0), "hp": [100.0, 100.0, 100.0, 100.0, 100.0, 100.0], "fortified": false, "order": "hold"}
    structures = [{"id": 0, "side": 0, "pos": Vector2(1000.0, 1200.0), "kind": "bunker", "sector": 0}]
    drone = {"id": 8, "side": 0, "pos": Vector2(2000.0, 1200.0), "state": "observing", "heading": 0.0, "charge": 100.0, "target": Vector2(2000.0, 1200.0)}
    verify(visible(Vector2(1999.0, 1200.0), [], [], {}, "prepare"), "preparation reveals friendly half without observers")
    verify(not visible(Vector2(2000.0, 1200.0), [unit], structures, drone, "prepare"), "preparation never reveals enemy side at boundary")
    verify(visible(Vector2(3999.0, 100.0), [], [], {}, "preparation", 1), "enemy preparation reveals its own half")
    verify(not visible(Vector2(1999.0, 100.0), [], [], {}, "prep", 1), "enemy preparation never sees friendly half")
    verify(not visible(Vector2(1000.0, 1200.0), [], structures), "empty owned bunker never supplies vision")
    verify(not visible(Vector2(500.0, 100.0), []), "without ownership data, empty ground is not inferred to be friendly")
    verify(visible(Vector2(2090.0, 1200.0), [unit]), "live friendly group can see across original boundary")
    verify(not visible(Vector2(2110.0, 1200.0), [unit]), "infantry vision stops beyond configured radius")
    verify(not visible(Vector2(-1.0, 1200.0), [unit]), "outside world remains hidden")
    verify(not visible(Vector2(4000.0, 1200.0), [], [], {}, "prep"), "preparation does not reveal outside map")
    var dead: Dictionary = unit.duplicate(true)
    dead.hp = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    verify(not visible(Vector2(1000.0, 1200.0), [dead], structures), "destroyed group provides no observation")
    dead.hp[3] = 1.0
    verify(visible(Vector2(1000.0, 1200.0), [dead]), "one surviving soldier still observes")
    var enemy: Dictionary = unit.duplicate(true)
    enemy.side = 1
    verify(not visible(Vector2(1000.0, 1200.0), [enemy]), "enemy observer cannot reveal player fog")
    verify(visible(Vector2(1000.0, 1200.0), [enemy], [], {}, "battle", 1), "enemy uses same infantry observation query")
    var moved: Dictionary = unit.duplicate(true)
    moved.pos = Vector2(3400.0, 1200.0)
    verify(not visible(Vector2(1000.0, 1200.0), [moved], structures), "group departure restores fog despite owned bunker")
    unit.fortified = true
    verify(is_equal_approx(visibility.observation_radius(unit, structures), 1375.0), "occupied fortified bunker grants exactly 25 percent")
    verify(visible(Vector2(2300.0, 1200.0), [unit], structures), "occupied bunker extends active group view")
    verify(visible(Vector2(2300.0, 1200.0), [unit]), "prepared field position grants occupied group extra radius")
    var hostile_site: Array = structures.duplicate(true)
    hostile_site[0].side = 1
    verify(visible(Vector2(2300.0, 1200.0), [unit], hostile_site), "prepared group bonus comes from occupation rather than remote site ownership")
    var far_site: Array = structures.duplicate(true)
    far_site[0].pos = Vector2(500.0, 1200.0)
    verify(visible(Vector2(2300.0, 1200.0), [unit], far_site), "field fortification does not need a nearby structure")
    unit.fortified = false
    verify(is_equal_approx(visibility.observation_radius(unit, structures), 1375.0), "stationary garrison gains existing bunker observation without buying it again")
    verify(is_equal_approx(visibility.observation_radius(unit, []), 1100.0), "bare stationary field gives only normal observation")
    unit.path = PackedVector2Array([unit.pos, Vector2(1400.0, 1200.0)])
    unit.path_next = 0
    verify(not visible(Vector2(2300.0, 1200.0), [unit], structures), "moving away from fortification removes its observation bonus")
    visibility.weather = "rain"
    verify(is_equal_approx(visibility.observation_radius(unit, structures), 825.0), "rain applies infantry vision multiplier")
    verify(not visible(Vector2(1900.0, 1200.0), [unit]), "rain hides target that clear weather reveals")
    visibility.weather = "fog"
    visibility.time_of_day = "night"
    verify(is_equal_approx(visibility.observation_radius(unit, structures), 247.5), "fog and night multiply infantry limitations")
    verify(is_equal_approx(visibility.drone_radius(), 427.5), "drone standard optics have same weather and darkness factors")
    verify(not visible(Vector2(2500.0, 1200.0), [], [], drone), "night fog hides distant drone target")
    visibility.weather = "clear"
    visibility.time_of_day = "dusk"
    verify(is_equal_approx(visibility.drone_radius(), 1330.0), "dusk lowers drone view")
    visibility.time_of_day = "day"
    verify(visible(Vector2(2800.0, 1200.0), [], [], drone), "observing drone reveals its forward sector")
    verify(not visible(Vector2(1600.0, 1200.0), [], [], drone), "drone cannot see behind its viewing sector")
    verify(not visible(Vector2(2000.0, 2000.0), [], [], drone), "drone sector excludes perpendicular target")
    verify(visible(Vector2(2600.0, 1800.0), [], [], drone), "drone sees inside 100 degree sector")
    verify(not visible(Vector2(2500.0, 2000.0), [], [], drone), "drone hides just outside sector")
    var destination: Dictionary = drone.duplicate(true)
    destination.target = Vector2(3200.0, 200.0)
    verify(visible(Vector2(2800.0, 1200.0), [], [], destination), "assigned target does not move actual drone observation origin")
    for state in ["ready", "flying", "returning", "charging"]:
        var inactive: Dictionary = drone.duplicate(true)
        inactive.state = state
        verify(not visible(Vector2(2800.0, 1200.0), [], [], inactive), "drone state %s supplies no vision" % state)
    var depleted: Dictionary = drone.duplicate(true)
    depleted.charge = 0.0
    verify(not visible(Vector2(2800.0, 1200.0), [], [], depleted), "empty drone battery supplies no vision")
    var opponent_drone: Dictionary = drone.duplicate(true)
    opponent_drone.side = 1
    verify(not visible(Vector2(2800.0, 1200.0), [], [], opponent_drone), "enemy drone cannot clear player fog")
    verify(visible(Vector2(2800.0, 1200.0), [], [], opponent_drone, "battle", 1), "optional enemy drone observes only for enemy")
    drone.heading = PI
    verify(visible(Vector2(1600.0, 1200.0), [], [], drone), "rotated drone observes actual new sector")
    verify(not visible(Vector2(2800.0, 1200.0), [], [], drone), "rotating drone restores fog to previous sector")
    drone.heading = 0.0
    # Full opaque building wall across the line of sight.
    for y in range(48):
        kinds[y * 80 + 28] = 3
    visibility.setup(grid, kinds, Vector2(4000.0, 2400.0), {})
    verify(not visible(Vector2(1800.0, 1200.0), [unit]), "buildings block infantry sight through wall")
    verify(not visibility.has_line_of_sight(Vector2(1000.0, 1200.0), Vector2(1800.0, 1200.0)), "public combat LOS cannot shoot through building wall")
    verify(not visibility.has_line_of_sight(Vector2(-1.0, 1200.0), Vector2(1300.0, 1200.0)), "public combat LOS rejects outside-world origin")
    verify(visible(Vector2(1300.0, 1200.0), [unit]), "building wall does not hide near side")
    var wall_drone: Dictionary = drone.duplicate(true)
    wall_drone.pos = Vector2(1000.0, 1200.0)
    verify(not visible(Vector2(1800.0, 1200.0), [], [], wall_drone), "drone does not reveal enemies through building walls")
    kinds[24 * 80 + 28] = 0
    visibility.setup(grid, kinds, Vector2(4000.0, 2400.0), {})
    verify(visible(Vector2(1800.0, 1200.0), [unit]), "opening gap in wall restores actual line of sight")
    reset_terrain()
    for x in range(24, 35):
        kinds[24 * 80 + x] = 2
    visibility.setup(grid, kinds, Vector2(4000.0, 2400.0), {})
    verify(not visible(Vector2(1900.0, 1200.0), [unit]), "deep woodland blocks infantry observation")
    verify(visible(Vector2(1300.0, 1200.0), [unit]), "infantry sees near edge of woods")
    verify(not visible(Vector2(1500.0, 1200.0), [], [], wall_drone), "drone optical canopy limit hides deep woodland")
    reset_terrain()
    var image: Image = visibility.build_fog_image([unit], structures, {}, "battle", Vector2i(80, 48))
    verify(image.get_size() == Vector2i(80, 48) and image.get_format() == Image.FORMAT_RGBA8, "fog image has requested world grid and alpha channel")
    verify(fog_alpha(image, Vector2(1000.0, 1200.0)) == 0.0, "image reveals currently observed infantry position")
    var departed_image: Image = visibility.build_fog_image([moved], structures, {}, "battle", Vector2i(80, 48))
    verify(fog_alpha(departed_image, Vector2(1000.0, 1200.0)) > 0.85, "regenerated fog forgets departed group with owned bunker")
    var drone_image: Image = visibility.build_fog_image([], [], drone, "battle", Vector2i(80, 48))
    var empty_image: Image = visibility.build_fog_image([], [], {}, "battle", Vector2i(80, 48))
    verify(fog_alpha(drone_image, Vector2(2800.0, 1200.0)) == 0.0 and fog_alpha(empty_image, Vector2(2800.0, 1200.0)) > 0.85, "removing drone restores fog image immediately")
    var prep_image: Image = visibility.build_fog_image([], [], drone, "prep", Vector2i(80, 48))
    verify(fog_alpha(prep_image, Vector2(1000.0, 1200.0)) == 0.0 and fog_alpha(prep_image, Vector2(2800.0, 1200.0)) > 0.85, "preparation image follows half-map rule despite active drone")
    # Validate every raster sample against authoritative detection, including
    # house occlusion, multiple observers, fortification and drone sector.
    kinds[24 * 80 + 27] = 3
    kinds[23 * 80 + 27] = 3
    visibility.setup(grid, kinds, Vector2(4000.0, 2400.0), {})
    var observers: Array = [unit, moved]
    image = visibility.build_fog_image(observers, structures, drone, "battle", Vector2i(80, 48))
    var disagreement := 0
    for y in range(48):
        for x in range(80):
            var point := Vector2((x + 0.5) * 50.0, (y + 0.5) * 50.0)
            if (image.get_pixel(x, y).a == 0.0) != visible(point, observers, structures, drone):
                disagreement += 1
    verify(disagreement == 0, "every fog raster sample equals actual enemy detection")
    var territory: Array = [
        {"rect": Rect2(0, 0, 2000, 2400), "owner": 0},
        {"rect": Rect2(2000, 0, 2000, 2400), "owner": 1}]
    visibility.sectors = territory
    var home_point := Vector2(100, 100)
    var away_point := Vector2(3500, 100)
    verify(visible(home_point, []), "empty owned half is always visible during battle")
    verify(not visible(away_point, []), "enemy territory stays hidden without current observers")
    verify(visible(away_point, [], [], {}, "battle", 1), "bot also sees its owned territory")
    visibility.weather = "fog"
    visibility.time_of_day = "night"
    verify(visible(home_point, []), "weather and darkness cannot cover owned territory with war fog")
    image = visibility.build_fog_image([], [], {}, "battle", Vector2i(80, 48))
    verify(fog_alpha(image, home_point) == 0 and fog_alpha(image, away_point) > 0.8, "fog raster opens owned ground and covers enemy ground")
    territory[0].owner = 1
    verify(not visible(home_point, []), "enemy capture immediately hides formerly owned territory")
    var nearby: Dictionary = unit.duplicate(true)
    nearby.pos = home_point
    verify(visible(home_point, [nearby]), "group can observe lost ground while it remains there")
    image = visibility.build_fog_image([], [], {}, "battle", Vector2i(80, 48))
    verify(fog_alpha(image, home_point) > 0.8, "fresh raster closes enemy-captured ground")
    territory[1].owner = 0
    verify(visible(away_point, []), "newly captured territory becomes permanently open while owned")
    image = visibility.build_fog_image([], [], {}, "battle", Vector2i(80, 48))
    verify(fog_alpha(image, away_point) == 0, "raster reveals captured enemy ground without a garrison")
    var mismatch := 0
    for y in range(48):
        for x in range(80):
            var point := Vector2((x + 0.5) * 50, (y + 0.5) * 50)
            if (image.get_pixel(x, y).a == 0) != visible(point, []):
                mismatch += 1
    verify(mismatch == 0, "all ownership fog samples agree with detection")
    visibility.sectors = []
    visibility.setup(grid, kinds, Vector2(4000.0, 2400.0), {"infantry_view": 500.0, "drone_view": 800.0, "drone_angle": 60.0, "boundary_x": 1000.0})
    verify(is_equal_approx(visibility.observation_radius(unit, []), 500.0) and is_equal_approx(visibility.drone_radius(), 800.0), "balance config controls observation ranges")
    verify(not visible(Vector2(1500.0, 1200.0), [], [], {}, "prep"), "configured boundary is honored")
    # Real full-world resolution timing is reported to catch expensive masks.
    var full_grid := AStarGrid2D.new()
    full_grid.region = Rect2i(0, 0, 418, 236)
    full_grid.cell_size = Vector2(12800.0 / 418.0, 7200.0 / 236.0)
    full_grid.update()
    var full_types := PackedByteArray()
    full_types.resize(418 * 236)
    visibility.setup(full_grid, full_types, Vector2(12800.0, 7200.0), {})
    var full_units: Array = []
    for pos in [Vector2(2000, 1700), Vector2(4000, 1700), Vector2(2000, 5000), Vector2(4000, 5000)]:
        var observer: Dictionary = unit.duplicate(true)
        observer.pos = pos
        full_units.append(observer)
    drone.pos = Vector2(6400.0, 3600.0)
    var started := Time.get_ticks_usec()
    var full_image: Image = visibility.build_fog_image(full_units, [], drone, "battle")
    print("FOG_V06_BUILD_USEC ", Time.get_ticks_usec() - started)
    verify(full_image.get_size() == Vector2i(128, 72), "default fog covers full map at bounded resolution")
    var nav_image: Image = load("res://assets/map/navigation_v0.5.1.png").get_image()
    for y in range(nav_image.get_height()):
        for x in range(nav_image.get_width()):
            var color := nav_image.get_pixel(x, y)
            full_types[y * 418 + x] = 3 if color.r < 0.18 and color.g < 0.18 and color.b < 0.18 else (2 if color.g > 0.72 and color.r < 0.25 and color.b < 0.25 else 0)
    visibility.setup(full_grid, full_types, Vector2(12800.0, 7200.0), {})
    started = Time.get_ticks_usec()
    full_image = visibility.build_fog_image(full_units, [], drone, "battle")
    print("FOG_V06_ACTUAL_MAP_BUILD_USEC ", Time.get_ticks_usec() - started)
    verify(full_image.get_size() == Vector2i(128, 72), "actual authored map produces current fog image")
    print("PASS_VISIBILITY_V06 checks=", checks) if failures.is_empty() else print("FAIL_VISIBILITY_V06 checks=", checks, " failures=", failures.size())
    quit(0 if failures.is_empty() else 1)
