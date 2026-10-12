extends Control

# v0.2.2: finger-sized graphics options and an audible, testable music loop.
# FPS cap and menu dust are real; map-quality options will come with the map.
const BACKDROP: Texture2D = preload("res://assets/loading_splash_ground.png")
const ATMOSPHERE_SCRIPT = preload("res://scripts/menu_atmosphere.gd")
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
var panel: ColorRect
var settings_title: Label
var volume_title: Label
var volume_value: Label
var volume_slider: HSlider
var music_test: Button
var music_status_label: Label
var fps_title: Label
var fps_30: Button
var fps_60: Button
var fps_value: Label
var fx_title: Label
var fx_none: Button
var fx_medium: Button
var fx_high: Button
var fx_description: Label
var brightness_title: Label
var brightness_value: Label
var brightness_slider: HSlider
var back_button: Button
var fps_check_clock: float = 0.0

var saved_volume: float = 70.0
var saved_fps: int = 60
var saved_effects: int = 1
var saved_brightness: float = 75.0

func _ready() -> void:
    _load_settings()
    MusicPlayer.ensure_playing()

    backdrop = TextureRect.new()
    backdrop.texture = BACKDROP
    backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(backdrop)

    atmosphere = Control.new()
    atmosphere.set_script(ATMOSPHERE_SCRIPT)
    atmosphere.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(atmosphere)

    dimmer = ColorRect.new()
    dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(dimmer)

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

    var start_btn := _button(menu_view, "НОВАЯ ИГРА", true)
    start_btn.tooltip_text = "Доступно после появления карты"
    menu_buttons.append(start_btn)
    var continue_btn := _button(menu_view, "ПРОДОЛЖИТЬ", true)
    continue_btn.tooltip_text = "Сохранённой кампании пока нет"
    menu_buttons.append(continue_btn)
    var settings_btn := _button(menu_view, "НАСТРОЙКИ", false)
    settings_btn.pressed.connect(_open_settings)
    menu_buttons.append(settings_btn)
    var exit_btn := _button(menu_view, "ВЫХОД", false)
    exit_btn.pressed.connect(func(): get_tree().quit())
    menu_buttons.append(exit_btn)
    version_label = _label(menu_view, "v0.2.2  •  МЕНЮ", 18, Color("#9da9a5"))

    settings_view = Control.new()
    settings_view.visible = false
    add_child(settings_view)
    shade = ColorRect.new()
    shade.color = Color(0.005, 0.012, 0.014, 0.55)
    shade.mouse_filter = Control.MOUSE_FILTER_STOP
    settings_view.add_child(shade)
    panel = ColorRect.new()
    panel.color = Color(0.038, 0.063, 0.071, 0.97)
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    settings_view.add_child(panel)

    settings_title = _label(settings_view, "НАСТРОЙКИ", 49, Color("#efefe2"))
    volume_title = _label(settings_view, "ГРОМКОСТЬ ИГРЫ", 31, Color("#e0e5dd"))
    volume_value = _label(settings_view, "70%", 30, Color("#e1e5d6"))
    volume_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    volume_slider = HSlider.new()
    volume_slider.min_value = 0.0
    volume_slider.max_value = 100.0
    volume_slider.step = 1.0
    volume_slider.value_changed.connect(_volume_changed)
    settings_view.add_child(volume_slider)

    music_test = _button(settings_view, "▶  ПРОВЕРИТЬ МУЗЫКУ", false, 27)
    music_test.pressed.connect(_test_music)
    music_status_label = _label(settings_view, "", 22, Color("#c4cfca"))

    fps_title = _label(settings_view, "ОГРАНИЧЕНИЕ КАДРОВ", 30, Color("#e0e5dd"))
    fps_30 = _button(settings_view, "30 FPS", false, 31)
    fps_60 = _button(settings_view, "60 FPS", false, 31)
    fps_30.pressed.connect(func(): _choose_fps(30))
    fps_60.pressed.connect(func(): _choose_fps(60))
    fps_value = _label(settings_view, "", 23, Color("#c4cfca"))

    fx_title = _label(settings_view, "АТМОСФЕРА МЕНЮ", 30, Color("#e0e5dd"))
    fx_none = _button(settings_view, "ВЫКЛ.", false, 29)
    fx_medium = _button(settings_view, "УМЕРЕННО", false, 29)
    fx_high = _button(settings_view, "ВЫСОКО", false, 29)
    fx_none.pressed.connect(func(): _choose_effects(0))
    fx_medium.pressed.connect(func(): _choose_effects(1))
    fx_high.pressed.connect(func(): _choose_effects(2))
    fx_description = _label(settings_view, "", 23, Color("#c4cfca"))

    brightness_title = _label(settings_view, "ЯРКОСТЬ ФОНА МЕНЮ", 30, Color("#e0e5dd"))
    brightness_value = _label(settings_view, "75%", 30, Color("#e1e5d6"))
    brightness_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    brightness_slider = HSlider.new()
    brightness_slider.min_value = 0.0
    brightness_slider.max_value = 100.0
    brightness_slider.step = 1.0
    brightness_slider.value_changed.connect(_brightness_changed)
    settings_view.add_child(brightness_slider)

    back_button = _button(settings_view, "НАЗАД", false, 33)
    back_button.pressed.connect(_close_settings)

    _apply_saved_settings()
    resized.connect(_layout)
    _layout()
    set_process(true)

func _label(parent: Control, caption: String, pts: int, tint: Color) -> Label:
    var output := Label.new()
    output.text = caption
    output.add_theme_font_size_override("font_size", pts)
    output.add_theme_color_override("font_color", tint)
    output.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    output.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(output)
    return output

func _button(parent: Control, caption: String, unavailable: bool, pts: int = 32) -> Button:
    var b := Button.new()
    b.text = caption
    b.disabled = unavailable
    b.focus_mode = Control.FOCUS_NONE
    b.alignment = HORIZONTAL_ALIGNMENT_CENTER
    b.add_theme_font_size_override("font_size", pts)
    b.add_theme_color_override("font_color", Color("#e9e8dd"))
    b.add_theme_color_override("font_disabled_color", Color("#7d8886"))
    _set_button_style(b, false)
    parent.add_child(b)
    return b

func _set_button_style(b: Button, selected: bool) -> void:
    var regular := StyleBoxFlat.new()
    regular.bg_color = Color("#344e47") if selected else Color("#101a1d")
    regular.border_color = Color("#d6d0a1") if selected else Color("#70807a")
    regular.set_border_width_all(3 if selected else 2)
    regular.set_corner_radius_all(12)
    b.add_theme_stylebox_override("normal", regular)
    var hover := regular.duplicate() as StyleBoxFlat
    hover.bg_color = Color("#3f6554") if selected else Color("#283d38")
    b.add_theme_stylebox_override("hover", hover)
    var pressed := regular.duplicate() as StyleBoxFlat
    pressed.bg_color = Color("#527662")
    b.add_theme_stylebox_override("pressed", pressed)
    var disabled_style := regular.duplicate() as StyleBoxFlat
    disabled_style.bg_color = Color(0.055, 0.068, 0.07, 0.64)
    disabled_style.border_color = Color(0.21, 0.26, 0.25, 0.56)
    b.add_theme_stylebox_override("disabled", disabled_style)

func _layout() -> void:
    if not is_instance_valid(backdrop):
        return
    for element in [backdrop, atmosphere, dimmer, settings_view]:
        element.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var panel_width := clampf(size.x * 0.26, 460.0, 650.0)
    left_panel.position = Vector2.ZERO
    left_panel.size = Vector2(panel_width, size.y)
    divider.position = Vector2(panel_width - 2.0, 0.0)
    divider.size = Vector2(2.0, size.y)
    menu_view.position = Vector2.ZERO
    menu_view.size = Vector2(panel_width, size.y)
    var padding := panel_width * 0.085
    var usable := panel_width - padding * 2.0
    menu_heading.position = Vector2(padding, size.y * 0.18)
    menu_heading.size = Vector2(usable, 66.0)
    menu_hint.position = Vector2(padding, size.y * 0.245)
    menu_hint.size = Vector2(usable, 42.0)
    var first_y := size.y * 0.37
    var gap := maxf(85.0, size.y * 0.105)
    for i in range(menu_buttons.size()):
        menu_buttons[i].position = Vector2(padding, first_y + gap * i)
        menu_buttons[i].size = Vector2(usable, 72.0)
    version_label.position = Vector2(padding, size.y - 80.0)
    version_label.size = Vector2(usable, 38.0)

    var mw := minf(1550.0, size.x * 0.93)
    var mh := minf(980.0, size.y * 0.94)
    var px := (size.x - mw) * 0.5
    var py := (size.y - mh) * 0.5
    panel.position = Vector2(px, py)
    panel.size = Vector2(mw, mh)
    var margin := mw * 0.056
    var x := px + margin
    var w := mw - 2.0 * margin
    var unit_y := mh / 980.0
    settings_title.position = Vector2(x, py + 25.0 * unit_y)
    settings_title.size = Vector2(w, 70.0 * unit_y)

    volume_title.position = Vector2(x, py + 115.0 * unit_y)
    volume_title.size = Vector2(w * 0.78, 50.0 * unit_y)
    volume_value.position = Vector2(x + w * 0.79, py + 115.0 * unit_y)
    volume_value.size = Vector2(w * 0.21, 50.0 * unit_y)
    volume_slider.position = Vector2(x, py + 173.0 * unit_y)
    volume_slider.size = Vector2(w, 52.0 * unit_y)
    music_test.position = Vector2(x, py + 235.0 * unit_y)
    music_test.size = Vector2(w * 0.43, 68.0 * unit_y)
    music_status_label.position = Vector2(x + w * 0.47, py + 235.0 * unit_y)
    music_status_label.size = Vector2(w * 0.53, 68.0 * unit_y)

    fps_title.position = Vector2(x, py + 324.0 * unit_y)
    fps_title.size = Vector2(w, 50.0 * unit_y)
    fps_30.position = Vector2(x, py + 381.0 * unit_y)
    fps_30.size = Vector2(w * 0.49, 80.0 * unit_y)
    fps_60.position = Vector2(x + w * 0.51, py + 381.0 * unit_y)
    fps_60.size = Vector2(w * 0.49, 80.0 * unit_y)
    fps_value.position = Vector2(x, py + 460.0 * unit_y)
    fps_value.size = Vector2(w, 42.0 * unit_y)

    fx_title.position = Vector2(x, py + 509.0 * unit_y)
    fx_title.size = Vector2(w, 52.0 * unit_y)
    fx_none.position = Vector2(x, py + 567.0 * unit_y)
    fx_none.size = Vector2(w * 0.30, 81.0 * unit_y)
    fx_medium.position = Vector2(x + w * 0.318, py + 567.0 * unit_y)
    fx_medium.size = Vector2(w * 0.365, 81.0 * unit_y)
    fx_high.position = Vector2(x + w * 0.701, py + 567.0 * unit_y)
    fx_high.size = Vector2(w * 0.299, 81.0 * unit_y)
    fx_description.position = Vector2(x, py + 651.0 * unit_y)
    fx_description.size = Vector2(w, 42.0 * unit_y)

    brightness_title.position = Vector2(x, py + 701.0 * unit_y)
    brightness_title.size = Vector2(w * 0.8, 50.0 * unit_y)
    brightness_value.position = Vector2(x + w * 0.80, py + 701.0 * unit_y)
    brightness_value.size = Vector2(w * 0.20, 50.0 * unit_y)
    brightness_slider.position = Vector2(x, py + 761.0 * unit_y)
    brightness_slider.size = Vector2(w, 52.0 * unit_y)

    back_button.position = Vector2(x, py + 862.0 * unit_y)
    back_button.size = Vector2(w, 82.0 * unit_y)

func _open_settings() -> void:
    menu_view.visible = false
    left_panel.visible = false
    divider.visible = false
    settings_view.visible = true
    settings_view.modulate.a = 0.0
    _refresh_music_status()
    create_tween().tween_property(settings_view, "modulate:a", 1.0, 0.2)

func _close_settings() -> void:
    settings_view.visible = false
    menu_view.visible = true
    left_panel.visible = true
    divider.visible = true

func _load_settings() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(PREFS_PATH) == OK:
        saved_volume = clampf(float(cfg.get_value("audio", "volume", 70.0)), 0.0, 100.0)
        saved_fps = 30 if int(cfg.get_value("video", "fps", 60)) == 30 else 60
        saved_effects = clampi(int(cfg.get_value("video", "effects", 1)), 0, 2)
        saved_brightness = clampf(float(cfg.get_value("video", "brightness", 75.0)), 0.0, 100.0)

func _save(section: String, key: String, value: Variant) -> void:
    var cfg := ConfigFile.new()
    cfg.load(PREFS_PATH)
    cfg.set_value(section, key, value)
    var result := cfg.save(PREFS_PATH)
    if result != OK:
        push_warning("Cannot save setting: %d" % result)

func _apply_saved_settings() -> void:
    volume_slider.set_value_no_signal(saved_volume)
    volume_value.text = "%d%%" % int(saved_volume)
    MusicPlayer.set_master_volume(saved_volume)
    Engine.max_fps = saved_fps
    _refresh_fps_buttons()
    atmosphere.call("set_effect_level", saved_effects)
    _refresh_fx_buttons()
    brightness_slider.set_value_no_signal(saved_brightness)
    brightness_value.text = "%d%%" % int(saved_brightness)
    _apply_brightness()
    _refresh_music_status()

func _refresh_fps_buttons() -> void:
    _set_button_style(fps_30, saved_fps == 30)
    _set_button_style(fps_60, saved_fps == 60)
    fps_value.text = "ЛИМИТ: %d FPS  •  ФАКТИЧЕСКИ: …" % saved_fps

func _refresh_fx_buttons() -> void:
    var count: int = [0, 26, 90][saved_effects]
    _set_button_style(fx_none, saved_effects == 0)
    _set_button_style(fx_medium, saved_effects == 1)
    _set_button_style(fx_high, saved_effects == 2)
    fx_description.text = "ЧАСТИЦ ПЫЛИ В МЕНЮ: %d.  НА КАРТУ ПОКА НЕ ВЛИЯЕТ." % count

func _apply_brightness() -> void:
    if is_instance_valid(dimmer):
        dimmer.color = Color(0.025, 0.035, 0.04, 0.55 - 0.40 * saved_brightness / 100.0)

func _volume_changed(value: float) -> void:
    saved_volume = value
    volume_value.text = "%d%%" % int(value)
    MusicPlayer.set_master_volume(value)
    _refresh_music_status()
    _save("audio", "volume", saved_volume)

func _choose_fps(value: int) -> void:
    saved_fps = value
    Engine.max_fps = saved_fps
    _refresh_fps_buttons()
    _save("video", "fps", saved_fps)

func _choose_effects(value: int) -> void:
    saved_effects = value
    atmosphere.call("set_effect_level", saved_effects)
    _refresh_fx_buttons()
    _save("video", "effects", saved_effects)

func _brightness_changed(value: float) -> void:
    saved_brightness = value
    brightness_value.text = "%d%%" % int(value)
    _apply_brightness()
    _save("video", "brightness", saved_brightness)

func _test_music() -> void:
    MusicPlayer.replay_theme()
    _refresh_music_status()

func _refresh_music_status() -> void:
    music_status_label.text = MusicPlayer.music_status()

func _process(delta: float) -> void:
    if not settings_view.visible:
        return
    fps_check_clock += delta
    if fps_check_clock >= 0.5:
        fps_check_clock = 0.0
        fps_value.text = "ЛИМИТ: %d FPS  •  ФАКТИЧЕСКИ: %d FPS" % [saved_fps, Engine.get_frames_per_second()]
        _refresh_music_status()

func _unhandled_input(event: InputEvent) -> void:
    if settings_view.visible and event.is_action_pressed("ui_cancel"):
        _close_settings()
        get_viewport().set_input_as_handled()
