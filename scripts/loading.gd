extends Control

# v0.1: a self-contained loading prototype. No fake percentages.
# Artwork and layout will be finalized with the player before v0.2.

const INTRO_SECONDS := 2.4
var elapsed: float = 0.0
var heading: Label
var subtitle: Label
var status: Label

func _ready() -> void:
    heading = _label("ЛИНИЯ ФРОНТА", 84, Color("#f2eee4"))
    subtitle = _label("КОМАНДИР БАТАЛЬОНА", 29, Color("#b7c0b4"))
    status = _label("ПОДГОТОВКА...", 23, Color("#d7dcd7"))
    get_viewport().size_changed.connect(_relayout)
    _relayout()

func _label(value: String, font_size: int, font_color: Color) -> Label:
    var lbl := Label.new()
    lbl.text = value
    lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    lbl.add_theme_font_size_override("font_size", font_size)
    lbl.add_theme_color_override("font_color", font_color)
    add_child(lbl)
    return lbl

func _relayout() -> void:
    var s := size
    heading.position = Vector2(s.x * 0.10, s.y * 0.34)
    heading.size = Vector2(s.x * 0.80, s.y * 0.13)
    subtitle.position = Vector2(s.x * 0.10, s.y * 0.47)
    subtitle.size = Vector2(s.x * 0.80, s.y * 0.06)
    status.position = Vector2(s.x * 0.30, s.y * 0.77)
    status.size = Vector2(s.x * 0.40, s.y * 0.06)
    queue_redraw()

func _process(delta: float) -> void:
    if elapsed < INTRO_SECONDS:
        elapsed += delta
        if elapsed >= INTRO_SECONDS:
            status.text = "ГОТОВО"
    queue_redraw()

func _draw() -> void:
    var s := size
    draw_rect(Rect2(Vector2.ZERO, s), Color("#17201a"))
    # Abstract top-down agricultural fields and narrow tree belts.
    for i in range(32):
        var t := float(i) / 32.0
        var x := t * s.x
        draw_line(Vector2(x - 180.0, 0), Vector2(x + 280.0, s.y), Color("#677057", 0.085), 13.0)
    for i in range(3):
        var y := s.y * (0.18 + i * 0.30)
        draw_line(Vector2(0, y), Vector2(s.x, y - s.y * 0.10), Color("#0b1713"), 67.0)
        draw_line(Vector2(0, y + 8), Vector2(s.x, y - s.y * 0.10 + 8), Color("#425047", 0.48), 12.0)
    draw_rect(Rect2(Vector2(0, s.y * 0.27), Vector2(s.x, s.y * 0.35)), Color("#080e0c", 0.71))
    var bar := Rect2(Vector2(s.x * 0.29, s.y * 0.86), Vector2(s.x * 0.42, 9.0))
    draw_rect(bar, Color("#647369", 0.40))
    if elapsed >= INTRO_SECONDS:
        draw_rect(bar, Color("#9aad8b"))
    else:
        var width := bar.size.x * 0.23
        var travel := fmod(elapsed / 1.1, 1.0)
        draw_rect(Rect2(Vector2(bar.position.x + travel * (bar.size.x - width), bar.position.y), Vector2(width, bar.size.y)), Color("#b8c8a6"))
