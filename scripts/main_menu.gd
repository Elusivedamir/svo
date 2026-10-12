extends Control

# v0.2: functional main menu shell. Map/save buttons unlock in later patches.
const BACKDROP = preload("res://assets/loading_splash_ground.png")
const PREFS_PATH := "user://settings.cfg"

var backdrop: TextureRect
var dimmer: ColorRect
var left_panel: ColorRect
var divider: ColorRect
var menu_view: Control
var settings_view: Control
var menu_heading: Label
var menu_hint: Label
var buttons: Array[Button] = []
var small_version: Label
var settings_heading: Label
var volume_heading: Label
var volume_value: Label
var volume_slider: HSlider
var back_button: Button

func _ready() -> void:
    backdrop = TextureRect.new()
    backdrop.texture = BACKDROP
    backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(backdrop)
    backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    dimmer = ColorRect.new()
    dimmer.color = Color(0.025, 0.035, 0.04, 0.33)
    dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(dimmer)
    dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

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
    menu_heading = _make_label(menu_view, "ГЛАВНОЕ МЕНЮ", 39, Color("#eceadd"))
    menu_hint = _make_label(menu_view, "ПОЛЕВАЯ КОМАНДНАЯ СИСТЕМА", 20, Color("#c7c8b8"))

    var start_btn := _make_button(menu_view, "НОВАЯ ИГРА", true)
    start_btn.tooltip_text = "Будет доступно после создания карты"
    buttons.append(start_btn)
    var continue_btn := _make_button(menu_view, "ПРОДОЛЖИТЬ", true)
    continue_btn.tooltip_text = "Пока нет сохранённой кампании"
    buttons.append(continue_btn)
    var settings_btn := _make_button(menu_view, "НАСТРОЙКИ", false)
    settings_btn.pressed.connect(_open_settings)
    buttons.append(settings_btn)
    var exit_btn := _make_button(menu_view, "ВЫХОД", false)
    exit_btn.pressed.connect(_exit_game)
    buttons.append(exit_btn)
    small_version = _make_label(menu_view, "v0.2  •  МЕНЮ", 18, Color("#9da9a5"))

    settings_view = Control.new()
    settings_view.visible = false
    add_child(settings_view)
    settings_heading = _make_label(settings_view, "НАСТРОЙКИ", 42, Color("#eceadd"))
    volume_heading = _make_label(settings_view, "ГРОМКОСТЬ ЗВУКА", 23, Color("#e5e7d7"))
    volume_value = _make_label(settings_view, "70%", 26, Color("#e5e7d7"))
    volume_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    volume_slider = HSlider.new()
    volume_slider.min_value = 0
    volume_slider.max_value = 100
    volume_slider.step = 1
    volume_slider.value = 70
    volume_slider.value_changed.connect(_update_volume)
    settings_view.add_child(volume_slider)
    back_button = _make_button(settings_view, "НАЗАД", false)
    back_button.pressed.connect(_close_settings)

    _restore_volume()
    resized.connect(_layout)
    _layout()

func _make_label(parent: Control, caption: String, font_size: int, tint: Color) -> Label:
    var label := Label.new()
    label.text = caption
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", tint)
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    parent.add_child(label)
    return label

func _make_button(parent: Control, caption: String, unavailable: bool) -> Button:
    var b := Button.new()
    b.text = caption
    b.disabled = unavailable
    b.focus_mode = Control.FOCUS_NONE
    b.alignment = HORIZONTAL_ALIGNMENT_CENTER
    b.add_theme_font_size_override("font_size", 32)
    b.add_theme_color_override("font_color", Color("#e9e8dd"))
    b.add_theme_color_override("font_disabled_color", Color("#7d8886"))
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color(0.065, 0.09, 0.11, 0.91)
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

func _layout() -> void:
    if not is_instance_valid(backdrop):
        return
    backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var pw := clampf(size.x * 0.26, 460.0, 650.0)
    left_panel.position = Vector2.ZERO
    left_panel.size = Vector2(pw, size.y)
    divider.position = Vector2(pw - 2.0, 0.0)
    divider.size = Vector2(2.0, size.y)
    menu_view.position = Vector2.ZERO
    menu_view.size = Vector2(pw, size.y)
    settings_view.position = Vector2.ZERO
    settings_view.size = Vector2(pw, size.y)

    var padding := pw * 0.085
    var usable := pw - 2.0 * padding
    menu_heading.position = Vector2(padding, size.y * 0.18)
    menu_heading.size = Vector2(usable, 66)
    menu_hint.position = Vector2(padding, size.y * 0.245)
    menu_hint.size = Vector2(usable, 42)
    var first_y := size.y * 0.37
    var button_gap := maxf(85.0, size.y * 0.105)
    for i in range(buttons.size()):
        buttons[i].position = Vector2(padding, first_y + button_gap * i)
        buttons[i].size = Vector2(usable, 72.0)
    small_version.position = Vector2(padding, size.y - 80.0)
    small_version.size = Vector2(usable, 38.0)

    settings_heading.position = Vector2(padding, size.y * 0.24)
    settings_heading.size = Vector2(usable, 60)
    volume_heading.position = Vector2(padding, size.y * 0.38)
    volume_heading.size = Vector2(usable * 0.75, 55)
    volume_value.position = Vector2(padding + usable * 0.75, size.y * 0.38)
    volume_value.size = Vector2(usable * 0.25, 55)
    volume_slider.position = Vector2(padding, size.y * 0.47)
    volume_slider.size = Vector2(usable, 50)
    back_button.position = Vector2(padding, size.y * 0.68)
    back_button.size = Vector2(usable, 75)

func _open_settings() -> void:
    menu_view.visible = false
    settings_view.visible = true

func _close_settings() -> void:
    settings_view.visible = false
    menu_view.visible = true

func _update_volume(value: float) -> void:
    volume_value.text = "%d%%" % int(value)
    var v := value / 100.0
    AudioServer.set_bus_mute(0, v <= 0.0)
    AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))
    var config := ConfigFile.new()
    config.set_value("audio", "volume", value)
    config.save(PREFS_PATH)

func _restore_volume() -> void:
    var config := ConfigFile.new()
    if config.load(PREFS_PATH) == OK:
        var value := clampf(float(config.get_value("audio", "volume", 70.0)), 0.0, 100.0)
        volume_slider.set_value_no_signal(value)
        volume_value.text = "%d%%" % int(value)
        AudioServer.set_bus_mute(0, value <= 0.0)
        AudioServer.set_bus_volume_db(0, linear_to_db(maxf(value / 100.0, 0.0001)))

func _exit_game() -> void:
    get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_cancel") and settings_view.visible:
        _close_settings()
        get_viewport().set_input_as_handled()
