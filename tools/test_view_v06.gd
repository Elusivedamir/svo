extends SceneTree

const View = preload("res://scripts/battle_view.gd")
const Visibility = preload("res://scripts/battle_visibility.gd")

class MockBattle extends RefCounted:
    var world_size := Vector2(12800, 7200)
    var nav: AStarGrid2D
    var nav_types := PackedByteArray()
    var units: Array = []
    var structures: Array = []
    var sectors: Array = []
    var drone: Dictionary = {}
    var phase := "prepare"
    var weather := "clear"
    var time_of_day := "day"
    var visibility: RefCounted

var checks := 0
var failures := 0

func _initialize() -> void:
    call_deferred("_run")

func _check(condition: bool, description: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        push_error("VIEW_V06: " + description)

func _unit(id: int, side: int, position: Vector2) -> Dictionary:
    return {"id": id, "side": side, "pos": position, "hp": [100, 100, 100, 100, 100, 100], "ammo": 120, "path": PackedVector2Array(), "path_next": 0, "order": "idle", "fortified": false, "facing": Vector2.RIGHT, "anim_time": 0.0, "shot_to": position, "shot_timer": 0.0}

func _run() -> void:
    var model := MockBattle.new()
    model.nav = AStarGrid2D.new()
    model.nav.region = Rect2i(0, 0, 418, 236)
    model.nav.cell_size = model.world_size / Vector2(model.nav.region.size)
    model.nav.offset = model.nav.cell_size * 0.5
    model.nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
    model.nav.update()
    model.nav_types.resize(418 * 236)
    # An impassable thin river through the formation exercises bridge/bank
    # compression rather than only checking a broad open field.
    for y in range(236):
        model.nav.set_point_solid(Vector2i(200, y), true)
        model.nav_types[y * 418 + 200] = 4
    var friendly := _unit(1, 0, Vector2(1600, 1800))
    var enemy := _unit(5, 1, Vector2(10000, 1800))
    model.units = [friendly, enemy]
    model.structures = [{"id": 1, "side": 0, "pos": friendly.pos, "kind": "bunker"}, {"id": 2, "side": 0, "pos": Vector2(1000, 6500), "kind": "post"}, {"id": 5, "side": 1, "pos": enemy.pos, "kind": "bunker"}]
    model.drone = {"side": 0, "pos": Vector2(1300, 1600), "target": Vector2(1300, 1600), "state": "ready", "charge": 100.0, "heading": 0.0}
    model.visibility = Visibility.new()
    model.visibility.setup(model.nav, model.nav_types, model.world_size, {})
    var camera := Camera2D.new()
    camera.zoom = Vector2.ONE * 0.375
    root.add_child(camera)
    var view := View.new()
    root.add_child(view)
    view.setup(model, camera)
    var positions: Array = view.soldier_positions(friendly)
    _check(positions.size() == 6, "six individual figures")
    _check(positions.duplicate().size() == 6 and positions[0] != positions[1] and positions[0] != positions[2] and positions[4] != positions[5], "distinct formation slots")
    for position in positions:
        _check(view._walkable(position), "normal formation has legal feet")
    _check(view.is_unit_visible(friendly), "own group remains known")
    _check(not view.is_unit_visible(enemy), "enemy half hidden during preparation")
    _check(view.squad_hit_test(enemy.pos, 0.375) == -1, "hidden enemy cannot be selected")
    _check(view.structure_hit_test(enemy.pos) == -1, "hidden bunker cannot be selected")
    _check(view.is_structure_visible(model.structures[1]), "own preparation post visible")
    _check(view.visible_units().size() == 1, "renderable units exclude hidden enemy")
    _check(view.visible_structures().size() == 2, "renderable sites exclude hidden bunker")
    _check(view.squad_hit_test(friendly.pos, 0.375) == 1, "own squad hit at centre")
    _check(view.drone_hit_test(model.drone.pos, 0.375), "drone hit at centre")
    _check(not view.drone_hit_test(model.drone.pos + Vector2(700, 0), 0.375), "drone misses distant tap")
    _check(view.fog_sprite.texture != null, "current-vision image becomes texture")
    _check(view.fog_sprite.z_index == -1 and view.atmosphere.z_index == -4, "terrain weather fog and soldiers ordered")
    model.phase = "battle"
    view.refresh_fog()
    _check(not view.is_structure_visible(model.structures[1]), "empty owned distant post grants no rendering")
    _check(not view.is_unit_visible(enemy), "far enemy stays hidden in battle")
    view.fog_enabled = false
    view.refresh_fog()
    _check(not view.fog_sprite.visible and not view.is_unit_visible(enemy), "debug fog toggle never reveals enemy actors")
    enemy.pos = friendly.pos + Vector2(300, 0)
    model.structures[2].pos = enemy.pos
    _check(view.is_unit_visible(enemy), "enemy visible only under current observation")
    _check(view.squad_hit_test(enemy.pos, 0.375) == 5, "observed enemy hit")
    _check(view.structure_hit_test(enemy.pos) == 5, "observed bunker hit")
    enemy.pos = Vector2(10000, 1800)
    model.structures[2].pos = enemy.pos
    _check(not view.is_unit_visible(enemy) and view.squad_hit_test(enemy.pos, 0.375) == -1, "lost observation immediately hides hit target")
    friendly.hp[2] = 0
    _check(view.soldier_positions(friendly).size() == 5, "loss removes a figure")
    friendly.hp = [0, 0, 0, 0, 0, 0]
    _check(not view.is_unit_visible(friendly) and view.squad_hit_test(friendly.pos, 0.375) == -1, "dead squad hidden and cannot be hit")
    friendly.hp = [100, 100, 100, 100, 100, 100]
    friendly.pos = model.nav.get_point_position(Vector2i(199, 100))
    positions = view.soldier_positions(friendly)
    _check(positions.size() == 6, "bank retains living figures")
    for position in positions:
        _check(view._walkable(position), "compressed bank figure never lies on water")
        _check(view._formation_reachable(friendly.pos, position), "formation cannot hop across river")
    var before: Vector2 = friendly.pos
    view.soldier_positions(friendly)
    view.squad_hit_test(friendly.pos)
    view.refresh_fog()
    _check(friendly.pos == before and model.units.size() == 2, "renderer never mutates simulation")
    model.time_of_day = "night"
    view.refresh_fog()
    _check(view.atmosphere.color.a >= 0.5, "night has visible terrain tint")
    model.time_of_day = "day"
    model.weather = "rain"
    view.refresh_fog()
    _check(view.atmosphere.color.a >= 0.15, "rain visibly darkens terrain")
    model.weather = "clear"
    view.refresh_fog()
    _check(is_zero_approx(view.atmosphere.color.a), "clear daylight restores natural map")
    # Execute every draw branch through actual scene-tree processing. Headless
    # rendering checks script execution, not GPU output or artwork appearance.
    view.selected_id = 1
    friendly.path = PackedVector2Array([friendly.pos, friendly.pos + Vector2(-300, 0)])
    friendly.order = "move"
    friendly.shot_to = friendly.pos + Vector2(-100, 0)
    friendly.shot_timer = 0.1
    model.drone.pos = friendly.pos
    model.drone.state = "observing"
    model.drone.heading = PI
    view.selected_drone = true
    model.weather = "rain"
    await process_frame
    await process_frame
    camera.zoom = Vector2.ONE * 0.19
    view.queue_redraw()
    await process_frame
    _check(view.is_inside_tree(), "view processes normal and overview scenes")
    view.queue_free()
    camera.queue_free()
    await process_frame
    if failures == 0:
        print("PASS_VIEW_V06 checks=", checks)
    else:
        print("FAIL_VIEW_V06 checks=", checks, " failures=", failures)
    quit(0 if failures == 0 else 1)
