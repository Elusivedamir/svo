extends "res://scripts/navigation_map_v051.gd"

# The old navigation and gesture component remains independently testable.
# Normal play uses the full battle model below; no legacy marker is drawn.
const MODEL_SCRIPT = preload("res://scripts/battle_model.gd")
const VISIBILITY_SCRIPT = preload("res://scripts/battle_visibility.gd")
const VIEW_SCRIPT = preload("res://scripts/battle_view.gd")
var legacy_regression_mode := false
var model
var view
var battle_config: Dictionary = {}
var selected_unit := 0
var selected_drone := false
var selected_post := false
var command_mode := "move"
var hud_panel: Panel
var territory_panel: Panel
var conditions_panel: Panel
var territory_label: Label
var phase_label: Label
var status_label: Label
var selection_label: Label
var start_button: Button
var pause_button: Button
var weather_option: OptionButton
var time_option: OptionButton
var unit_buttons: Array[Button] = []
var drone_button: Button
var post_button: Button
var mode_buttons: Dictionary = {}
var place_button: Button
var cancel_place_button: Button
var overview_button: Button
var conditions_button: Button
var commands_button: Button
var conditions_open := false
var commands_open := true
var placement_pending := false
var placement_point := Vector2.ZERO
var placement_valid := false
var arranged_positions: Dictionary = {}
var _hud_timer := 0.0
var _battle_message := ""
var _message_timer := 0.0
const WEATHER_KEYS := ["clear", "rain", "fog"]
const TIME_KEYS := ["day", "dusk", "night"]

func _create_camera_controls() -> void:
    if legacy_regression_mode:
        super._create_camera_controls()
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/battle_v06.json"))
    if not parsed is Dictionary:
        push_error("Battle configuration could not be loaded")
        return
    battle_config = parsed
    var visibility = VISIBILITY_SCRIPT.new()
    visibility.setup(nav, nav_types, WORLD_SIZE, battle_config)
    model = MODEL_SCRIPT.new()
    model.setup(nav, nav_types, WORLD_SIZE, visibility, battle_config)
    view = VIEW_SCRIPT.new()
    add_child(view)
    view.setup(model, camera)
    _build_battle_hud()
    _select_unit(0)
    print("SMOKE_BATTLE_READY")

func _panel(name_text: String) -> Panel:
    # Fixed panel bounds: wrapped text must never resize the touch-blocking background.
    var panel := Panel.new()
    panel.name = name_text
    panel.mouse_filter = Control.MOUSE_FILTER_STOP
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.025, 0.055, 0.06, 0.95)
    style.border_color = Color(0.34, 0.56, 0.48, 0.85)
    style.set_border_width_all(2)
    style.set_corner_radius_all(12)
    style.content_margin_left = 16.0
    style.content_margin_right = 16.0
    style.content_margin_top = 12.0
    style.content_margin_bottom = 12.0
    panel.add_theme_stylebox_override("panel", style)
    camera_controls.add_child(panel)
    return panel

func _label(text_value: String, font_size: int = 26) -> Label:
    var label := Label.new()
    label.text = text_value
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", Color("#e4f4eb"))
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return label

func _button(text_value: String, node_name: String, callback: Callable, minimum: Vector2 = Vector2(150, 64)) -> Button:
    var button := Button.new()
    button.text = text_value
    button.name = node_name
    button.custom_minimum_size = minimum
    button.focus_mode = Control.FOCUS_NONE
    button.mouse_filter = Control.MOUSE_FILTER_STOP
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button.add_theme_font_size_override("font_size", 24)
    button.add_theme_color_override("font_color", Color("#ecf8ee"))
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.04, 0.11, 0.10, 0.97)
    style.border_color = Color(0.36, 0.63, 0.51)
    style.set_border_width_all(2)
    style.set_corner_radius_all(10)
    button.add_theme_stylebox_override("normal", style)
    button.add_theme_stylebox_override("hover", style.duplicate())
    var pressed := style.duplicate() as StyleBoxFlat
    pressed.bg_color = Color(0.14, 0.30, 0.21)
    button.add_theme_stylebox_override("pressed", pressed)
    button.pressed.connect(callback)
    return button

func _build_battle_hud() -> void:
    camera_controls = CanvasLayer.new()
    camera_controls.name = "BattleControls"
    camera_controls.layer = 20
    add_child(camera_controls)
    territory_panel = _panel("Territory")
    territory_label = _label("НАШИ 50%   |   ПРОТИВНИК 50%", 28)
    territory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    territory_panel.add_child(territory_label)
    phase_label = _label("ПОДГОТОВКА · БЕЗ ТАЙМЕРА", 24)
    phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    territory_panel.add_child(phase_label)
    conditions_panel = _panel("Conditions")
    weather_option = OptionButton.new()
    weather_option.name = "Weather"
    time_option = OptionButton.new()
    time_option.name = "TimeOfDay"
    for option: OptionButton in [weather_option, time_option]:
        option.focus_mode = Control.FOCUS_NONE
        option.add_theme_font_size_override("font_size", 26)
        conditions_panel.add_child(option)
    for text_value: String in ["Ясно", "Дождь", "Туман"]:
        weather_option.add_item(text_value)
    for text_value: String in ["День", "Сумерки", "Ночь"]:
        time_option.add_item(text_value)
    weather_option.item_selected.connect(_set_weather)
    time_option.item_selected.connect(_set_time)
    focus_button = _button("К ОТРЯДУ", "FocusMarker", _focus_marker, Vector2(320, 88))
    start_button = _button("НАЧАТЬ БОЙ", "StartBattle", _start_battle, Vector2(360, 88))
    pause_button = _button("ПАУЗА", "PauseBattle", _toggle_pause, Vector2(360, 88))
    overview_button = _button("НАШЕ ПОЛЕ", "Overview", _overview, Vector2(300, 88))
    conditions_button = _button("ПОГОДА / ВРЕМЯ", "ConditionsToggle", _toggle_conditions, Vector2(300, 88))
    for button in [focus_button, start_button, pause_button, overview_button, conditions_button]:
        camera_controls.add_child(button)
    hud_panel = _panel("BattlePanel")
    for id in range(4):
        var button := _button("Блиндаж " + str(id + 1), "Group" + str(id + 1), _select_unit.bind(id), Vector2(190, 82))
        hud_panel.add_child(button)
        unit_buttons.append(button)
    drone_button = _button("Дрон", "SelectDrone", _select_drone, Vector2(150, 82))
    post_button = _button("НП", "SelectPost", _select_post, Vector2(150, 82))
    commands_button = _button("ПРИКАЗЫ ▾", "CommandsToggle", _toggle_commands, Vector2(210, 82))
    for button in [drone_button, post_button, commands_button]:
        hud_panel.add_child(button)
    selection_label = _label("БЛИНДАЖ 1", 26)
    selection_label.clip_text = true
    hud_panel.add_child(selection_label)
    status_label = _label("Выберите блиндаж, затем место на карте", 24)
    status_label.clip_text = true
    hud_panel.add_child(status_label)
    place_button = _button("ПОСТАВИТЬ", "ConfirmPlacement", _confirm_placement, Vector2(280, 80))
    cancel_place_button = _button("ОТМЕНА", "CancelPlacement", _cancel_placement, Vector2(220, 80))
    hud_panel.add_child(place_button)
    hud_panel.add_child(cancel_place_button)
    var captions := {"move": "Двигаться", "capture": "Занять", "assault": "Штурм", "stop": "СТОП", "fortify": "Закрепиться", "reinforce": "Пополнить", "resupply": "Боезапас", "return_drone": "Вернуть дрон"}
    for key: String in captions:
        var button := _button(captions[key], key, _choose_command.bind(key), Vector2(150, 80))
        hud_panel.add_child(button)
        mode_buttons[key] = button
    _update_battle_hud()
    _layout_camera_controls()

func _rect(control: Control, position_value: Vector2, size_value: Vector2) -> void:
    control.position = position_value
    control.size = size_value

func _layout_camera_controls() -> void:
    if legacy_regression_mode:
        super._layout_camera_controls()
        return
    if not is_instance_valid(hud_panel):
        return
    var viewport: Vector2 = get_viewport_rect().size
    var margin: float = clampf(minf(viewport.x, viewport.y) * 0.02, 12.0, 24.0)
    var width := minf(2040.0, viewport.x - margin * 2.0)
    var expanded: bool = model != null and (model.phase == "prepare" or commands_open)
    _rect(hud_panel, Vector2((viewport.x - width) * 0.5, viewport.y - (236.0 if expanded else 146.0) - margin), Vector2(width, 236.0 if expanded else 146.0))
    var selector_width := (width - 32.0 - 6.0 * 8.0) / 7.0
    var selectors: Array = unit_buttons.duplicate()
    selectors.append_array([drone_button, post_button, commands_button])
    for index in range(selectors.size()):
        _rect(selectors[index], Vector2(16.0 + index * (selector_width + 8.0), 12.0), Vector2(selector_width, 82.0))
    _rect(selection_label, Vector2(16, 101), Vector2(width * 0.4 - 16, 38))
    _rect(status_label, Vector2(width * 0.4, 101), Vector2(width * 0.6 - 16, 38))
    var command_width := (width - 32.0 - 7.0 * 8.0) / 8.0
    var index := 0
    for button in mode_buttons.values():
        _rect(button, Vector2(16 + index * (command_width + 8), 146), Vector2(command_width, 80))
        index += 1
    _rect(place_button, Vector2(16, 146), Vector2(360, 80))
    _rect(cancel_place_button, Vector2(388, 146), Vector2(240, 80))
    _rect(territory_panel, Vector2((viewport.x - 600.0) * 0.5, margin), Vector2(600, 106))
    _rect(territory_label, Vector2(12, 10), Vector2(576, 42))
    _rect(phase_label, Vector2(12, 57), Vector2(576, 36))
    _rect(overview_button, Vector2(margin, margin), Vector2(300, 88))
    _rect(conditions_button, Vector2(margin, margin + 100), Vector2(300, 88))
    _rect(conditions_panel, Vector2(margin, margin + 200), Vector2(500, 106))
    _rect(weather_option, Vector2(12, 12), Vector2(232, 82))
    _rect(time_option, Vector2(256, 12), Vector2(232, 82))
    _rect(focus_button, Vector2(viewport.x - 360 - margin, margin), Vector2(360, 88))
    _rect(start_button, Vector2(viewport.x - 360 - margin, margin + 100), Vector2(360, 88))
    _rect(pause_button, start_button.position, start_button.size)

func _toggle_conditions() -> void:
    _cancel_touch_gesture()
    conditions_open = not conditions_open
    _update_battle_hud()

func _toggle_commands() -> void:
    _cancel_touch_gesture()
    commands_open = not commands_open
    _update_battle_hud()
    _layout_camera_controls()

func _overview() -> void:
    _cancel_touch_gesture()
    camera.zoom = Vector2.ONE * clampf(minf(get_viewport_rect().size.x / (WORLD_SIZE.x * 0.55), get_viewport_rect().size.y / WORLD_SIZE.y), camera_min_zoom, camera_max_zoom)
    camera.position = WORLD_SIZE * Vector2(0.25, 0.5)
    _clamp_camera()

func _cancel_placement() -> void:
    placement_pending = false
    placement_valid = false
    queue_redraw()
    _update_battle_hud()

func _preview_placement(point: Vector2) -> void:
    placement_point = point
    placement_pending = true
    placement_valid = model.can_place(point, 8 if selected_post else selected_unit)
    if placement_valid:
        placement_point = nav.get_point_position(_cell_from_world(point))
    _update_battle_hud()
    queue_redraw()

func _confirm_placement() -> void:
    _cancel_touch_gesture()
    if model == null or model.phase != "prepare" or not placement_pending or not placement_valid:
        return
    var accepted: bool = model.relocate_post(placement_point) if selected_post else model.relocate(selected_unit, placement_point)
    if accepted:
        arranged_positions["post" if selected_post else str(selected_unit)] = true
        _cancel_placement()
        _notice("Позиция поставлена. Выберите следующий блиндаж")
    else:
        _notice(str(model.last_error))

func _camera_button_contains(screen_point: Vector2) -> bool:
    if legacy_regression_mode:
        return super._camera_button_contains(screen_point)
    for control in [hud_panel, territory_panel, conditions_panel, focus_button, start_button, pause_button, overview_button, conditions_button]:
        if is_instance_valid(control) and control.visible and control.get_global_rect().has_point(screen_point):
            return true
    return false

func _select_unit(id: int) -> void:
    _cancel_touch_gesture()
    _cancel_placement()
    selected_unit = id
    selected_drone = false
    selected_post = false
    command_mode = "move"
    _sync_selection()

func _select_drone() -> void:
    _cancel_touch_gesture()
    _cancel_placement()
    selected_unit = -1
    selected_drone = true
    selected_post = false
    command_mode = "move"
    _sync_selection()

func _select_post() -> void:
    _cancel_touch_gesture()
    _cancel_placement()
    selected_unit = -1
    selected_drone = false
    selected_post = true
    command_mode = "move"
    _sync_selection()

func _sync_selection() -> void:
    if view != null:
        view.selected_id = selected_unit
        view.selected_drone = selected_drone
        view.target_mode = command_mode
        view.queue_redraw()
    _update_battle_hud()

func _notice(text_value: String) -> void:
    _battle_message = text_value
    _message_timer = 3.0
    _update_battle_hud()

func _choose_command(key: String) -> void:
    _cancel_touch_gesture()
    if model == null or model.phase == "ended":
        return
    if key == "return_drone":
        model.return_drone()
    elif selected_drone and key == "capture":
        command_mode = "sector"
        _notice("Тапните направление обзора дрона")
    elif key == "stop":
        if selected_drone:
            model.return_drone()
        elif selected_unit >= 0:
            model.order_stop(selected_unit)
    elif key == "fortify" and selected_unit >= 0:
        if not model.order_fortify(selected_unit):
            _notice(str(model.last_error))
    elif key == "reinforce" and selected_unit >= 0:
        if not model.reinforce(selected_unit):
            _notice("Пополнение: блиндаж, вне боя, запас снабжения")
    elif key == "resupply" and selected_unit >= 0:
        if not model.resupply(selected_unit):
            _notice("Боезапас: блиндаж, вне боя, запас снабжения")
    else:
        command_mode = key
        if key == "capture" or key == "assault":
            _notice("Тапните участок для захвата")
    _sync_selection()

func _handle_map_tap(screen_point: Vector2) -> void:
    if legacy_regression_mode:
        super._handle_map_tap(screen_point)
        return
    if model == null or model.phase == "ended" or model.paused:
        return
    var point: Vector2 = _screen_to_world(screen_point)
    # In setup the explicitly selected bunker wins over marker hit tests.
    # A nearby group must not silently change the position being placed.
    if model.phase == "prepare" and not selected_drone and (selected_unit >= 0 or selected_post):
        _preview_placement(point)
        return
    var hit: int = view.squad_hit_test(point, camera.zoom.x)
    if hit >= 0:
        var unit: Dictionary = model.unit_by_id(hit)
        if not unit.is_empty() and int(unit.side) == 0:
            _select_unit(hit)
            return
    if view.drone_hit_test(point, camera.zoom.x):
        _select_drone()
        return
    if selected_drone:
        if command_mode == "sector":
            var drone_pos: Vector2 = model.drone.pos
            model.drone.heading = (point - drone_pos).angle()
            _notice("Направление обзора задано")
        elif not model.assign_drone(point, float(model.drone.get("heading", 0.0))):
            _notice("Точка вне дальности связи дрона")
        _update_battle_hud()
        return
    if selected_post:
        if model.phase == "prepare":
            if not model.relocate_post(point):
                _notice("НП размещается на доступной суше нашей половины")
        else:
            _notice("После начала боя НП остаётся на своей позиции")
        return
    if selected_unit < 0:
        _notice("Выберите одну из четырёх групп")
        return
    var accepted := false
    if model.phase == "prepare":
        accepted = model.relocate(selected_unit, point)
    elif command_mode == "capture" or command_mode == "assault" or hit >= 0:
        accepted = model.order_capture(selected_unit, point)
    else:
        accepted = model.order_move(selected_unit, point)
    if not accepted:
        blocked_at = point
        blocked_timer = 0.7
        _notice("Здесь нет допустимого прохода или позиции")
    _update_battle_hud()

func _focus_marker() -> void:
    if legacy_regression_mode:
        super._focus_marker()
        return
    _cancel_touch_gesture()
    if model == null:
        return
    if selected_drone:
        camera.position = model.drone.pos
    elif selected_post:
        for structure in model.structures:
            if structure.kind == "post" and int(structure.side) == 0:
                camera.position = structure.pos
                break
    elif selected_unit >= 0:
        var unit: Dictionary = model.unit_by_id(selected_unit)
        if not unit.is_empty():
            camera.position = unit.pos
    _clamp_camera()

func _set_weather(index: int) -> void:
    if model != null and model.phase == "prepare":
        model.weather = WEATHER_KEYS[index]
        model.visibility.weather = model.weather
        _update_battle_hud()

func _set_time(index: int) -> void:
    if model != null and model.phase == "prepare":
        model.time_of_day = TIME_KEYS[index]
        model.visibility.time_of_day = model.time_of_day
        _update_battle_hud()

func _start_battle() -> void:
    _cancel_touch_gesture()
    if model == null:
        return
    if model.phase == "ended":
        var visibility = model.visibility
        model.setup(nav, nav_types, WORLD_SIZE, visibility, battle_config)
        arranged_positions.clear()
        _cancel_placement()
        weather_option.select(0)
        time_option.select(0)
        _select_unit(0)
        _focus_marker()
    elif placement_pending:
        _notice("Сначала поставьте позицию или отмените выбор места")
    elif not model.start_battle():
        _notice("Все четыре группы и НП должны стоять на допустимых местах")
    _update_battle_hud()

func _toggle_pause() -> void:
    _cancel_touch_gesture()
    if model != null and model.phase == "battle":
        model.paused = not model.paused
        _update_battle_hud()

func _process(delta: float) -> void:
    if legacy_regression_mode:
        super._process(delta)
        return
    if model == null:
        return
    model.advance(delta)
    if blocked_timer > 0.0:
        blocked_timer = maxf(0.0, blocked_timer - delta)
        queue_redraw()
    _message_timer = maxf(0.0, _message_timer - delta)
    _hud_timer -= delta
    if _hud_timer <= 0.0:
        _hud_timer = 0.15
        _update_battle_hud()

func _update_battle_hud() -> void:
    if model == null or not is_instance_valid(status_label):
        return
    territory_label.text = "НАШИ %.1f%%   |   ПРОТИВНИК %.1f%%" % [model.percent(0), model.percent(1)]
    var preparing: bool = model.phase == "prepare"
    var ended: bool = model.phase == "ended"
    if preparing:
        phase_label.text = "ПОДГОТОВКА · БЕЗ ТАЙМЕРА"
    elif ended:
        phase_label.text = "НИЧЬЯ" if int(model.winner) == -2 else ("ПОБЕДА" if int(model.winner) == 0 else "ПОРАЖЕНИЕ")
    else:
        phase_label.text = "ПАУЗА" if model.paused else "БОЙ · ЗАХВАТ И УДЕРЖАНИЕ"
    start_button.visible = preparing or ended
    start_button.text = "ЗАНОВО" if ended else "НАЧАТЬ БОЙ"
    pause_button.visible = not preparing and not ended
    pause_button.text = "ПРОДОЛЖИТЬ" if model.paused else "ПАУЗА"
    conditions_button.visible = preparing
    conditions_panel.visible = preparing and conditions_open
    place_button.visible = preparing and not selected_drone
    cancel_place_button.visible = preparing and not selected_drone
    place_button.disabled = not placement_pending or not placement_valid or selected_drone
    cancel_place_button.disabled = not placement_pending
    commands_button.visible = not preparing
    commands_button.text = "ПРИКАЗЫ ▴" if commands_open else "ПРИКАЗЫ ▾"
    weather_option.disabled = not preparing
    time_option.disabled = not preparing
    for id in range(unit_buttons.size()):
        var unit: Dictionary = model.unit_by_id(id)
        var count: int = model.alive_count(unit) if not unit.is_empty() else 0
        unit_buttons[id].text = ("Блиндаж %d%s" % [id + 1, " ✓" if arranged_positions.has(str(id)) else ""]) if preparing else "Группа %d · %d" % [id + 1, count]
        unit_buttons[id].modulate = Color("#80ffd0") if id == selected_unit else Color.WHITE
        unit_buttons[id].disabled = count == 0
    focus_button.text = "К ДРОНУ" if selected_drone else ("К НП" if selected_post else ("К БЛИНДАЖУ" if preparing else "К ОТРЯДУ"))
    var status := ""
    if selected_drone:
        var states := {"ready": "Готов", "flying": "Летит", "observing": "Наблюдает", "returning": "Возвращается", "charging": "Заряжается"}
        selection_label.text = "ДРОН · %s · ЗАРЯД %d%%" % [states.get(model.drone.state, model.drone.state), roundi(float(model.drone.charge))]
        status = "Тап: точка наблюдения. «Сектор»: направление"
    elif selected_post:
        selection_label.text = "НАБЛЮДАТЕЛЬНЫЙ ПОСТ"
        status = "Тап: переставить НП на своей половине" if preparing else "НП обеспечивает связь с дроном"
    elif selected_unit >= 0:
        var unit: Dictionary = model.unit_by_id(selected_unit)
        if not unit.is_empty():
            selection_label.text = ("БЛИНДАЖ %d · ВЫБЕРИТЕ МЕСТО" % [selected_unit + 1]) if preparing else "ГРУППА %d · %d/%d · БЗ %d" % [selected_unit + 1, model.alive_count(unit), int(battle_config.get("squad_size", 6)), roundi(float(unit.ammo))]
            var orders := {"idle": "Ожидает", "move": "Движется", "capture": "Захватывает", "fortify": "Закрепляется", "dead": "Уничтожена", "hold": "Удерживает"}
            status = "Тап по карте → «Поставить»" if preparing else str(orders.get(unit.order, unit.order))
            if model.alive_count(unit) == 0:
                status = "Группа уничтожена"
    else:
        selection_label.text = "ВЫБЕРИТЕ ГРУППУ ИЛИ ДРОН"
    if _message_timer > 0.0:
        status = _battle_message
    if preparing and placement_pending:
        status = "Место выбрано → «Поставить»" if placement_valid else str(model.last_error)
    status_label.text = status + " · Снабжение %d" % roundi(float(model.supplies[0]))
    if ended:
        var survivors := 0
        for unit in model.units:
            if int(unit.side) == 0:
                survivors += model.alive_count(unit)
        var roster: int = 4 * int(battle_config.get("squad_size", 6))
        status_label.text = "Наши потери: %d из %d. Нажмите «Заново»" % [roster - survivors, roster]
    for key in mode_buttons:
        var button: Button = mode_buttons[key]
        button.visible = (not preparing and commands_open) or (preparing and selected_drone and key in ["move", "capture", "return_drone"])
        button.disabled = ended or model.paused
        if selected_drone:
            button.disabled = button.disabled or key not in ["move", "capture", "stop", "return_drone"]
        elif selected_post:
            button.disabled = button.disabled or key != "move" or not preparing
        else:
            button.disabled = button.disabled or selected_unit < 0 or (preparing and key != "move") or key == "return_drone"
            if selected_unit >= 0:
                button.disabled = button.disabled or model.alive_count(model.unit_by_id(selected_unit)) == 0
    mode_buttons["move"].text = "Переставить" if preparing and not selected_drone else "Двигаться"
    mode_buttons["capture"].text = "Сектор" if selected_drone else "Занять"
    _layout_camera_controls()

func _notification(what: int) -> void:
    super._notification(what)
    if not legacy_regression_mode and model != null and model.phase == "battle":
        if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
            model.paused = true
            _update_battle_hud()

func _draw() -> void:
    if legacy_regression_mode:
        super._draw()
    elif is_instance_valid(camera):
        if placement_pending:
            var color := Color(0.3, 1.0, 0.65, 0.9) if placement_valid else Color(1.0, 0.25, 0.2, 0.9)
            var radius := 42.0 / camera.zoom.x
            draw_circle(placement_point, radius, Color(color, 0.16))
            draw_arc(placement_point, radius, 0.0, TAU, 48, color, 3.0 / camera.zoom.x, true)
            var ghost_size := Vector2(54, 32) / camera.zoom
            draw_rect(Rect2(placement_point - ghost_size * 0.5, ghost_size), color, false, 3.0 / camera.zoom.x)
        if blocked_timer > 0.0:
            draw_arc(blocked_at, 24.0 / camera.zoom.x, 0.0, TAU, 32, Color(1.0, 0.30, 0.25, blocked_timer), 4.0 / camera.zoom.x, true)
