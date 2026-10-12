extends Control

# Approved v0.1.2 splash remains unchanged. Move to main menu after it finishes.
const BACKGROUND_PATH: String = "res://assets/loading_splash_ground.png"
const MENU_PATH: String = "res://scenes/main_menu.tscn"
const INTRO_DURATION: float = 1.8

var background: TextureRect
var progress_track: ColorRect
var progress_segment: ColorRect
var status_label: Label
var is_ready := false
var failed := false
var load_request_started := false
var phase := 0.0
var elapsed := 0.0
var finished_visual_intro := false

func _ready() -> void:
    background = TextureRect.new()
    background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)
    background.modulate.a = 0.0
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    progress_track = ColorRect.new()
    progress_track.color = Color(1, 1, 1, 0.25)
    progress_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(progress_track)

    progress_segment = ColorRect.new()
    progress_segment.color = Color(0.96, 0.96, 0.94)
    progress_segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(progress_segment)

    status_label = Label.new()
    status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    status_label.add_theme_font_size_override("font_size", 27)
    status_label.add_theme_color_override("font_color", Color(0.96, 0.96, 0.94))
    status_label.text = "ПОДГОТОВКА ЭКРАНА…"
    add_child(status_label)

    resized.connect(_layout)
    _layout()
    var err := ResourceLoader.load_threaded_request(BACKGROUND_PATH, "Texture2D")
    if err == OK:
        load_request_started = true
    else:
        _fail()

func _layout() -> void:
    if is_instance_valid(background):
        background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    if is_instance_valid(status_label):
        status_label.position = Vector2(size.x * 0.30, size.y * 0.88)
        status_label.size = Vector2(size.x * 0.40, maxf(size.y * 0.06, 40.0))
    if is_instance_valid(progress_track):
        progress_track.position = Vector2(size.x * 0.35, size.y * 0.855)
        progress_track.size = Vector2(size.x * 0.30, maxf(size.y * 0.006, 5.0))
    _position_segment()

func _position_segment() -> void:
    if not is_instance_valid(progress_track) or not is_instance_valid(progress_segment):
        return
    var width := progress_track.size.x
    var seg_width := width * 0.23
    progress_segment.size = Vector2(seg_width, progress_track.size.y)
    progress_segment.position = progress_track.position + Vector2(fmod(phase * 0.8, 1.0) * (width - seg_width), 0.0)

func _process(delta: float) -> void:
    phase += delta
    elapsed += delta
    if load_request_started and not is_ready and not failed:
        var state := ResourceLoader.load_threaded_get_status(BACKGROUND_PATH)
        if state == ResourceLoader.THREAD_LOAD_LOADED:
            var texture := ResourceLoader.load_threaded_get(BACKGROUND_PATH) as Texture2D
            if texture == null:
                _fail()
            else:
                background.texture = texture
                is_ready = true
                var intro := create_tween()
                intro.tween_property(background, "modulate:a", 1.0, 0.85)
        elif state == ResourceLoader.THREAD_LOAD_FAILED or state == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
            _fail()
    if is_ready and elapsed >= INTRO_DURATION and not finished_visual_intro:
        finished_visual_intro = true
        status_label.text = "ГОТОВО"
        var fade := create_tween()
        fade.set_parallel(true)
        fade.tween_property(progress_track, "modulate:a", 0.0, 0.4)
        fade.tween_property(progress_segment, "modulate:a", 0.0, 0.4)
        get_tree().create_timer(0.75).timeout.connect(_open_main_menu)
    _position_segment()

func _open_main_menu() -> void:
    if not failed and is_inside_tree():
        var result := get_tree().change_scene_to_file(MENU_PATH)
        if result != OK:
            _fail()

func _fail() -> void:
    failed = true
    status_label.text = "ОШИБКА ЗАГРУЗКИ"
    progress_track.visible = false
    progress_segment.visible = false
