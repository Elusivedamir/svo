extends Control

# v0.2.3: restored stable menu with enlarged touch dropdowns, persistent settings.
const BACKDROP: Texture2D = preload("res://assets/loading_splash_ground.png")
const AMBIENCE_SCRIPT = preload("res://scripts/menu_atmosphere.gd")
const PREFS_PATH := "user://settings.cfg"

var backdrop: TextureRect
var atmosphere: Control
var dimmer: ColorRect
var left_panel: ColorRect
var divider: ColorRect
var menu_view: Control
var menu_heading: Label
var menu_hint: Label
var menu_buttons: Array[Button] = []
var version_label: Label

var settings_view: Control
var shade: ColorRect
var modal_panel: ColorRect
var settings_title: Label
var volume_title: Label
var volume_value: Label
var volume_slider: HSlider
var fps_title: Label
var fps_choice: OptionButton
var fx_title: Label
var fx_choice: OptionButton
var brightness_title: Label
var brightness_value: Label
var brightness_slider: HSlider
var back_button: Button

var saved_volume: float = 70.0
var saved_fps: int = 60
var saved_effects: int = 1
var saved_brightness: float = 75.0

func _ready() -> void:
    _read_prefs()

    backdrop = TextureRect.new()
    backdrop.texture = BACKDROP
    backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(backdrop)

    atmosphere = Control.new()
    atmosphere.set_script(AMBIENCE_SCRIPT)
    atmosphere.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(atmosphere)
    atmosphere.call("set_effect_level", saved_effects)

    dimmer = ColorRect.new()
    dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(dimmer)
    _apply_brightness()

    left_panel = ColorRect.new()
    left_panel.color = Color(0.035, 0.055, 0.06, 0.84)
    left_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(left_panel)

    divider = ColorRect.new()
    divider.color = Color(0.70, 0.69, 0.54, 0.63)
    divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(divider)

    menu_view = Control.new()
    add_child(menu_view)
    menu_heading = _label(menu_view, "ГЛАВНОЕ МЕНЮ", 39, Color("#eceadd"))
    menu_hint = _label(menu_view, "ПОЛЕВАЯ КОМАНДНАЯ СИСТЕМА", 20, Color("#c7c8b8"))

    var new_game := _button(menu_view, "НОВАЯ ИГРА", false)
    new_game.tooltip_text = "Открыть карту полей и лесополос"
    menu_buttons.append(new_game)
    new_game.pressed.connect(_start_new_game)
    var cont := _button(menu_view, "ПРОДОЛЖИТЬ", true)
    cont.tooltip_text = "Пока нет сохранённой кампании"
    menu_buttons.append(cont)
    var options := _button(menu_view, "НАСТРОЙКИ", false)
    options.pressed.connect(_open_settings)
    menu_buttons.append(options)
    var exit_btn := _button(menu_view, "ВЫХОД", false)
    exit_btn.pressed.connect(_exit_game)
    menu_buttons.append(exit_btn)
    version_label = _label(menu_view, "v0.3.0  •  МЕНЮ", 18, Color("#9da9a5"))

    settings_view = Control.new()
    settings_view.visible = false
    add_child(settings_view)

    shade = ColorRect.new()
    shade.color = Color(0.005, 0.012, 0.014, 0.48)
    shade.mouse_filter = Control.MOUSE_FILTER_STOP
    settings_view.add_child(shade)

    modal_panel = ColorRect.new()
    modal_panel.color = Color(0.038, 0.063, 0.071, 0.96)
    modal_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    settings_view.add_child(modal_panel)

    settings_title = _label(settings_view, "НАСТРОЙКИ", 43, Color("#efefe2"))
    volume_title = _label(settings_view, "ГРОМКОСТЬ МУЗЫКИ И ЗВУКА", 24, Color("#e0e5dd"))
    volume_value = _label(settings_view, "70%", 25, Color("#d6dbc9"))
    volume_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    volume_slider = HSlider.new()
    volume_slider.min_value = 0.0
    volume_slider.max_value = 100.0
    volume_slider.step = 1.0
    volume_slider.value = saved_volume
    volume_slider.value_changed.connect(_volume_changed)
    settings_view.add_child(volume_slider)

    fps_title = _label(settings_view, "ЧАСТОТА КАДРОВ", 24, Color("#e0e5dd"))
    fps_choice = _choice(settings_view)
    fps_choice.add_item("30 FPS", 30)
    fps_choice.add_item("60 FPS", 60)
    fps_choice.item_selected.connect(_fps_changed)

    fx_title = _label(settings_view, "АТМОСФЕРНЫЕ ЭФФЕКТЫ", 24, Color("#e0e5dd"))
    fx_choice = _choice(settings_view)
    fx_choice.add_item("Выключены", 0)
    fx_choice.add_item("Умеренные", 1)
    fx_choice.add_item("Высокие", 2)
    fx_choice.item_selected.connect(_fx_changed)

    brightness_title = _label(settings_view, "ЯРКОСТЬ ФОНА", 24, Color("#e0e5dd"))
    brightness_value = _label(settings_view, "75%", 25, Color("#d6dbc9"))
    brightness_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    brightness_slider = HSlider.new()
    brightness_slider.min_value = 0.0
    brightness_slider.max_value = 100.0
    brightness_slider.step = 1.0
    brightness_slider.value = saved_brightness
    brightness_slider.value_changed.connect(_brightness_changed)
    settings_view.add_child(brightness_slider)

    back_button = _button(settings_view, "НАЗАД", false)
    back_button.pressed.connect(_close_settings)

    _apply_loaded_values()
    resized.connect(_layout)
    _layout()
    print("SMOKE_MAIN_MENU_READY")
    print("SMOKE_NEW_GAME_BUTTON_ACTIVE")

func _label(parent: Control, caption: String, pts: int, tint: Color) -> Label:
    var result := Label.new()
    result.text = caption
    result.add_theme_font_size_override("font_size", pts)
    result.add_theme_color_override("font_color", tint)
    result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    result.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(result)
    return result

func _button(parent: Control, caption: String, unavailable: bool) -> Button:
    var b := Button.new()
    b.text = caption
    b.disabled = unavailable
    b.focus_mode = Control.FOCUS_NONE
    b.alignment = HORIZONTAL_ALIGNMENT_CENTER
    b.add_theme_font_size_override("font_size", 32)
    b.add_theme_color_override("font_color", Color("#e9e8dd"))
    b.add_theme_color_override("font_disabled_color", Color("#7d8886"))
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color(0.065, 0.09, 0.11, 0.93)
    normal.border_color = Color(0.40, 0.48, 0.44, 0.82)
    normal.set_border_width_all(2)
    normal.set_corner_radius_all(10)
    b.add_theme_stylebox_override("normal", normal)
    var hover := normal.duplicate() as StyleBoxFlat
    hover.bg_color = Color(0.18, 0.26, 0.24, 0.97)
    b.add_theme_stylebox_override("hover", hover)
    var pressed := normal.duplicate() as StyleBoxFlat
    pressed.bg_color = Color(0.21, 0.29, 0.23, 0.98)
    b.add_theme_stylebox_override("pressed", pressed)
    var disabled_style := normal.duplicate() as StyleBoxFlat
    disabled_style.bg_color = Color(0.055, 0.068, 0.07, 0.64)
    disabled_style.border_color = Color(0.21, 0.26, 0.25, 0.56)
    b.add_theme_stylebox_override("disabled", disabled_style)
    parent.add_child(b)
    return b

func _choice(parent: Control) -> OptionButton:
    var o := OptionButton.new()
    o.add_theme_font_size_override("font_size", 33)
    o.get_popup().add_theme_font_size_override("font_size", 40)
    o.get_popup().add_theme_constant_override("v_separation", 20)
    o.focus_mode = Control.FOCUS_NONE
    parent.add_child(o)
    return o

func _layout() -> void:
    if not is_instance_valid(backdrop):
        return
    for child in [backdrop, atmosphere, dimmer, settings_view]:
        child.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var pw: float = clampf(size.x * 0.26, 460.0, 650.0)
    left_panel.position = Vector2.ZERO
    left_panel.size = Vector2(pw, size.y)
    divider.position = Vector2(pw - 2.0, 0.0)
    divider.size = Vector2(2.0, size.y)
    menu_view.position = Vector2.ZERO
    menu_view.size = Vector2(pw, size.y)

    var padding: float = pw * 0.085
    var usable: float = pw - 2.0 * padding
    menu_heading.position = Vector2(padding, size.y * 0.18)
    menu_heading.size = Vector2(usable, 66)
    menu_hint.position = Vector2(padding, size.y * 0.245)
    menu_hint.size = Vector2(usable, 42)
    var first_y: float = size.y * 0.37
    var gap: float = maxf(85.0, size.y * 0.105)
    for i in range(menu_buttons.size()):
        menu_buttons[i].position = Vector2(padding, first_y + gap * i)
        menu_buttons[i].size = Vector2(usable, 72)
    version_label.position = Vector2(padding, size.y - 80.0)
    version_label.size = Vector2(usable, 38)

    var modal_w: float = minf(1070.0, size.x * 0.84)
    var modal_h: float = minf(780.0, size.y * 0.87)
    var px: float = (size.x - modal_w) * 0.5
    var py: float = (size.y - modal_h) * 0.5
    modal_panel.position = Vector2(px, py)
    modal_panel.size = Vector2(modal_w, modal_h)
    var x: float = px + 72.0
    var width: float = modal_w - 144.0
    settings_title.position = Vector2(x, py + 34)
    settings_title.size = Vector2(width, 68)
    var row0: float = py + 143
    volume_title.position = Vector2(x, row0)
    volume_title.size = Vector2(width * 0.78, 45)
    volume_value.position = Vector2(x + width * 0.78, row0)
    volume_value.size = Vector2(width * 0.22, 45)
    volume_slider.position = Vector2(x, row0 + 57)
    volume_slider.size = Vector2(width, 40)

    var row1: float = py + 270
    fps_title.position = Vector2(x, row1)
    fps_title.size = Vector2(width * 0.52, 55)
    fps_choice.position = Vector2(x + width * 0.58, row1)
    fps_choice.size = Vector2(width * 0.42, 56)

    var row2: float = py + 360
    fx_title.position = Vector2(x, row2)
    fx_title.size = Vector2(width * 0.58, 55)
    fx_choice.position = Vector2(x + width * 0.58, row2)
    fx_choice.size = Vector2(width * 0.42, 56)

    var row3: float = py + 475
    brightness_title.position = Vector2(x, row3)
    brightness_title.size = Vector2(width * 0.78, 50)
    brightness_value.position = Vector2(x + width * 0.78, row3)
    brightness_value.size = Vector2(width * 0.22, 50)
    brightness_slider.position = Vector2(x, row3 + 55)
    brightness_slider.size = Vector2(width, 40)

    back_button.position = Vector2(x, py + modal_h - 111)
    back_button.size = Vector2(width, 70)

func _open_settings() -> void:
    menu_view.visible = false
    left_panel.visible = false
    divider.visible = false
    settings_view.visible = true
    settings_view.modulate.a = 0.0
    create_tween().tween_property(settings_view, "modulate:a", 1.0, 0.2)

func _close_settings() -> void:
    settings_view.visible = false
    menu_view.visible = true
    left_panel.visible = true
    divider.visible = true

func _read_prefs() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(PREFS_PATH) == OK:
        saved_volume = clampf(float(cfg.get_value("audio", "volume", 70.0)), 0.0, 100.0)
        saved_fps = 30 if int(cfg.get_value("video", "fps", 60)) == 30 else 60
        saved_effects = clampi(int(cfg.get_value("video", "effects", 1)), 0, 2)
        saved_brightness = clampf(float(cfg.get_value("video", "brightness", 75.0)), 0.0, 100.0)

func _save(key_section: String, key: String, value: Variant) -> void:
    var cfg := ConfigFile.new()
    cfg.load(PREFS_PATH)
    cfg.set_value(key_section, key, value)
    var error: Error = cfg.save(PREFS_PATH)
    if error != OK:
        push_warning("Settings not saved: %d" % error)

func _apply_loaded_values() -> void:
    volume_slider.set_value_no_signal(saved_volume)
    volume_value.text = "%d%%" % int(saved_volume)
    _apply_volume()
    fps_choice.select(0 if saved_fps == 30 else 1)
    Engine.max_fps = saved_fps
    fx_choice.select(saved_effects)
    atmosphere.call("set_effect_level", saved_effects)
    brightness_slider.set_value_no_signal(saved_brightness)
    brightness_value.text = "%d%%" % int(saved_brightness)
    _apply_brightness()

func _apply_volume() -> void:
    AudioServer.set_bus_mute(0, saved_volume <= 0.0)
    AudioServer.set_bus_volume_db(0, linear_to_db(maxf(saved_volume / 100.0, 0.0001)))

func _apply_brightness() -> void:
    if is_instance_valid(dimmer):
        dimmer.color = Color(0.025, 0.035, 0.04, 0.55 - 0.40 * saved_brightness / 100.0)

func _volume_changed(value: float) -> void:
    saved_volume = value
    volume_value.text = "%d%%" % int(value)
    _apply_volume()
    _save("audio", "volume", saved_volume)

func _fps_changed(index: int) -> void:
    saved_fps = 30 if index == 0 else 60
    Engine.max_fps = saved_fps
    _save("video", "fps", saved_fps)

func _fx_changed(index: int) -> void:
    saved_effects = clampi(index, 0, 2)
    atmosphere.call("set_effect_level", saved_effects)
    _save("video", "effects", saved_effects)

func _brightness_changed(value: float) -> void:
    saved_brightness = value
    brightness_value.text = "%d%%" % int(value)
    _apply_brightness()
    _save("video", "brightness", saved_brightness)

func _exit_game() -> void:
    get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
    if settings_view.visible and event.is_action_pressed("ui_cancel"):
        _close_settings()
        get_viewport().set_input_as_handled()

func _start_new_game() -> void:
    var result := get_tree().change_scene_to_file("res://scenes/world_map.tscn")
    if result != OK:
        push_error("Could not open the map scene: %d" % result)
