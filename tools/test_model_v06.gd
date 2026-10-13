extends SceneTree

const Model = preload("res://scripts/battle_model.gd")
const Visibility = preload("res://scripts/battle_visibility.gd")
const WORLD := Vector2(12800, 7200)
var failures: Array[String] = []
var checks := 0
var settings: Dictionary
var grid: AStarGrid2D
var types := PackedByteArray()

func _initialize() -> void:
    call_deferred("run_checks")

func verify(ok: bool, caption: String) -> void:
    checks += 1
    print("PASS " if ok else "FAIL ", caption)
    if not ok:
        failures.append(caption)

func fixture(ai := false, combat := false):
    var vision = Visibility.new()
    vision.setup(grid, types, WORLD, settings)
    var battle = Model.new()
    battle.setup(grid, types, WORLD, vision, settings)
    battle.ai_enabled = ai
    battle.combat_enabled = combat
    return battle

func run_checks() -> void:
    settings = JSON.parse_string(FileAccess.get_file_as_string("res://data/battle_v06.json"))
    grid = AStarGrid2D.new()
    grid.region = Rect2i(0, 0, 128, 72)
    grid.cell_size = WORLD / Vector2(grid.region.size)
    grid.offset = grid.cell_size * 0.5
    grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
    grid.update()
    types.resize(128 * 72)
    types.fill(0)
    test_setup()
    test_navigation()
    test_capture()
    test_supply()
    test_combat()
    test_drone()
    test_ai()
    test_victory()
    if failures.is_empty():
        print("PASS_MODEL_V06 checks=", checks)
    else:
        push_error("FAIL_MODEL_V06 " + str(failures))
    quit(0 if failures.is_empty() else 1)

func test_setup() -> void:
    var battle = fixture(true, true)
    verify(battle.units.size() == 8 and battle.structures.size() == 9 and battle.sectors.size() == 8, "four infantry positions per side and one observation post")
    var legal := true
    for unit in battle.units:
        legal = legal and battle.legal_point(unit.pos, int(unit.side)) and battle.alive_count(unit) == 6
    verify(legal, "all generated six-person groups stand on their own connected half")
    verify(battle.percent(0) == 50.0 and battle.percent(1) == 50.0, "initial control is 50/50")
    var positions: Array = []
    for unit in battle.units:
        positions.append(unit.pos)
    battle.advance(86400.0)
    var unchanged: bool = battle.elapsed == 0.0 and battle.drone.charge == 100.0
    for index in range(8):
        unchanged = unchanged and battle.units[index].pos == positions[index]
    verify(unchanged and battle.phase == "prepare", "unlimited preparation freezes AI, combat, charge and the clock")
    verify(not battle.relocate(0, Vector2(9000, 1800)), "deployment rejects enemy half")
    verify(battle.relocate(0, Vector2(2100, 2100)) and battle.structures[0].pos == battle.units[0].pos, "repositioning moves infantry and its own bunker together")
    verify(battle.relocate_post(Vector2(5000, 3500)) and battle.drone.pos == battle.structures[8].pos, "repositioning post moves the docked drone")
    var saved: Vector2 = battle.units[0].pos
    verify(not battle.relocate(0, battle.units[1].pos) and battle.units[0].pos == saved, "overlapping bunker positions are rejected without moving the group")
    verify(not battle.relocate_post(battle.units[1].pos), "observation post cannot overlap another bunker")
    var bridge_point := Vector2(2200, 2200)
    var bridge_cell: Vector2i = battle._cell(bridge_point)
    var bridge_index: int = bridge_cell.y * battle.nav_size.x + bridge_cell.x
    var original: int = battle.nav_types[bridge_index]
    battle.nav_types[bridge_index] = 5
    verify(not battle.relocate(0, bridge_point), "bunker cannot occupy a walkable bridge")
    battle.nav_types[bridge_index] = original
    verify(battle.start_battle(), "valid deployment starts the battle")
    verify(not battle.relocate(0, Vector2(1000, 1000)), "battle locks deployment")

func test_navigation() -> void:
    var battle = fixture()
    battle.start_battle()
    var unit: Dictionary = battle.units[0]
    var origin: Vector2 = unit.pos
    var destination: Vector2 = grid.get_point_position(Vector2i(25, 18))
    verify(battle.order_move(0, destination), "living group accepts an accessible route")
    battle.advance(0.25)
    verify(unit.pos != origin and unit.pos != destination and unit.anim_time > 0.0, "movement advances over time and drives walking animation")
    battle.order_stop(0)
    origin = unit.pos
    battle.advance(2.0)
    verify(unit.pos == origin and unit.path.is_empty(), "stop preserves the exact mid-route position")
    battle.order_move(0, destination)
    var safe := true
    for tick in range(150):
        battle.advance(0.05)
        safe = safe and battle.legal_point(unit.pos)
    verify(safe and unit.pos.distance_to(destination) < 0.1, "route reaches its destination without closed terrain")
    battle.paused = true
    var elapsed: float = battle.elapsed
    origin = unit.pos
    battle.advance(100.0)
    verify(battle.elapsed == elapsed and unit.pos == origin and not battle.order_move(0, origin + Vector2(400, 0)), "pause freezes simulation and rejects movement orders")

func test_capture() -> void:
    var battle = fixture()
    battle.start_battle()
    var unit: Dictionary = battle.units[0]
    var sector: Dictionary = battle.sectors[2]
    battle.units[4].pos = Vector2(9500, 1000)
    var point := Vector2(7200, 1800)
    unit.pos = grid.get_point_position(battle._cell(point))
    verify(battle.order_capture(0, point) and unit.path[-1] == unit.pos, "capture respects the clicked field point rather than the sector centre")
    battle.advance(19.9)
    verify(sector.owner == 1 and sector.capture_progress > 19.0, "ownership requires the full capture duration")
    battle.advance(0.15)
    verify(sector.owner == 0 and battle.percent(0) == 62.5 and battle.structures[4].side == 1, "field capture changes control without claiming a remote bunker")
    verify(battle.supplies[0] == 100.0, "ordinary field capture gives no bunker loot")
    unit.pos = battle.structures[4].pos
    verify(battle.order_capture(0, unit.pos), "hostile bunker can be captured inside an already owned sector")
    battle.advance(20.1)
    verify(battle.structures[4].side == 0 and battle.supplies[0] == 200.0, "first bunker capture transfers ownership and supplies")
    battle.structures[4].side = 1
    sector.owner = 1
    battle.order_capture(0, unit.pos)
    battle.advance(20.1)
    verify(battle.structures[4].side == 0 and battle.supplies[0] == 200.0, "recapture never farms extra supplies")
    unit.pos = Vector2(100, 100)
    verify(sector.owner == 0 and battle.visibility.is_visible(sector.pos, 0, battle.units, battle.structures, battle.drone, battle.phase), "owned sector stays visible after its group leaves")
    sector.owner = 1
    verify(not battle.visibility.is_visible(sector.pos, 0, battle.units, battle.structures, battle.drone, battle.phase), "enemy recapture restores fog in an empty sector")
    battle = fixture()
    battle.start_battle()
    unit = battle.units[0]
    unit.pos = battle.sectors[2].pos
    battle.order_capture(0, unit.pos)
    battle.advance(25.0)
    verify(battle.sectors[2].owner == 1 and battle.sectors[2].capture_progress == 0.0, "living enemy garrison contests capture")
    battle = fixture(false, true)
    battle.start_battle()
    unit = battle.units[0]
    unit.pos = battle.sectors[2].pos - Vector2(600, 0)
    battle.order_capture(0, unit.pos)
    battle.advance(1.0)
    verify(battle.sectors[2].capture_progress == 0.0 and unit.hp[0] < 100.0, "capture cannot progress while an enemy outside the occupation radius fires on the group")

func test_supply() -> void:
    var battle = fixture()
    battle.start_battle()
    var unit: Dictionary = battle.units[0]
    unit.hp[0] = 0.0
    verify(battle.reinforce(0) and battle.alive_count(unit) == 6 and battle.supplies[0] == 80.0, "bunker replaces one lost soldier at configured cost")
    verify(not battle.reinforce(0) and battle.supplies[0] == 80.0, "full roster cannot spend supply or grow")
    unit.ammo = 1.0
    verify(battle.resupply(0) and unit.ammo == settings.squad_ammo and battle.supplies[0] == 70.0, "resupply restores ammunition at an owned bunker")
    unit.pos += Vector2(700, 0)
    unit.hp[0] = 0.0
    verify(not battle.reinforce(0), "reinforcement requires a nearby bunker")
    for index in range(unit.hp.size()):
        unit.hp[index] = 0.0
    unit.pos = battle.structures[0].pos
    verify(not battle.reinforce(0), "supplies cannot resurrect a completely lost group")
    battle = fixture()
    battle.start_battle()
    unit = battle.units[0]
    unit.fortified = false
    unit.pos += Vector2(700, 0)
    verify(battle.order_fortify(0), "living group can prepare its owned field position")
    battle.advance(4.9)
    verify(not unit.fortified and battle.supplies[0] == 100.0, "field preparation takes time and does not charge before completion")
    battle.advance(0.15)
    verify(unit.fortified and battle.supplies[0] == 70.0, "completed field position consumes configured supplies")
    verify(not battle.order_fortify(0) and battle.supplies[0] == 70.0, "already prepared position cannot charge repeatedly")

func duel():
    var battle = fixture(false, true)
    battle.start_battle()
    battle.units[0].pos = Vector2(5900, 1800)
    battle.units[4].pos = Vector2(6400, 1800)
    battle.units[0].fortified = false
    battle.units[4].fortified = false
    return battle

func test_combat() -> void:
    var first = duel()
    first.advance(0.05)
    verify(first.units[0].hp[0] < 100.0 and is_equal_approx(first.units[0].hp[0], first.units[4].hp[0]), "simultaneous equal volleys affect both sides symmetrically")
    verify(first.units[0].ammo == settings.squad_ammo - 6.0 and first.units[4].ammo == settings.squad_ammo - 6.0, "shooting consumes actual rounds")
    var second = duel()
    for tick in range(20):
        second.advance(0.05)
    var third = duel()
    third.advance(1.0)
    verify(second.units[0].hp == third.units[0].hp and second.units[4].hp == third.units[4].hp, "damage is independent of frame batching")
    first = duel()
    first.units[0].ammo = 0.0
    first.advance(0.05)
    verify(first.units[4].hp[0] == 100.0 and first.units[0].hp[0] < 100.0, "empty ammo prevents shooting without immunity")
    first = duel()
    first.units[4].fortified = true
    first.advance(0.05)
    verify(first.units[4].hp[0] > first.units[0].hp[0], "prepared cover reduces incoming damage")

func test_drone() -> void:
    var battle = fixture()
    var target: Vector2 = battle.structures[8].pos + Vector2(1400, 0)
    verify(battle.assign_drone(target) and battle.drone.state == "ready", "preparation records a planned flight without free scouting")
    battle.advance(100.0)
    verify(battle.drone.charge == 100.0 and battle.drone.pos == battle.structures[8].pos, "planning does not consume battery")
    battle.start_battle()
    verify(battle.drone.state == "flying", "battle starts the planned flight")
    battle.advance(3.0)
    verify(battle.drone.state == "observing" and battle.drone.pos == target and battle.drone.charge < 100.0, "drone really arrives, observes and consumes charge")
    battle.return_drone()
    verify(battle.drone.state == "returning", "return immediately stops drone observation")
    battle.advance(20.0)
    verify(battle.drone.state == "ready" and battle.drone.pos == battle.structures[8].pos and battle.drone.charge == 100.0, "return and dock recharge complete physically")
    verify(not battle.assign_drone(Vector2(12700, 100)), "drone is limited by post radio range")

func test_ai() -> void:
    var first = fixture(true, false)
    var second = fixture(true, false)
    for unit in second.units:
        if int(unit.side) == 0:
            unit.pos = Vector2(1000, 1000)
    first.start_battle()
    second.start_battle()
    first.advance(2.05)
    second.advance(2.05)
    var same := true
    var active := false
    for id in range(4, 8):
        same = same and first.units[id].path == second.units[id].path
        active = active or not first.units[id].path.is_empty()
    verify(active, "running bot issues genuine capture routes")
    verify(same, "unseen friendly coordinates do not change bot orders")

func test_victory() -> void:
    var battle = fixture()
    battle.config.victory_hold_seconds = 0.3
    battle.start_battle()
    for index in range(6):
        battle.sectors[index].owner = 0
    battle.advance(0.2)
    verify(battle.phase == "battle", "territory threshold must be held for the full duration")
    battle.advance(0.15)
    verify(battle.phase == "ended" and battle.winner == 0, "holding dominant territory produces victory")
    var time: float = battle.elapsed
    battle.advance(100.0)
    verify(battle.elapsed == time, "ended match stops simulation")
    battle = fixture()
    battle.start_battle()
    for unit in battle.units:
        if int(unit.side) == 0:
            for index in range(unit.hp.size()):
                unit.hp[index] = 0.0
    battle.advance(0.05)
    verify(battle.phase == "ended" and battle.winner == 1, "losing every group causes defeat")
