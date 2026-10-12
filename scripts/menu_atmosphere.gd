extends Control

# Subtle, purely visual drifting dust. Presets adjust actual rendering load.
var effect_level: int = 1
var elapsed: float = 0.0

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_effect_level(level: int) -> void:
    effect_level = clampi(level, 0, 2)
    set_process(effect_level > 0)
    queue_redraw()

func _process(delta: float) -> void:
    elapsed += delta
    queue_redraw()

func _draw() -> void:
    if effect_level == 0:
        return
    var count: int = 16 if effect_level == 1 else 45
    var w: float = maxf(size.x, 1.0)
    var h: float = maxf(size.y, 1.0)
    for i in range(count):
        var f: float = float(i)
        var x: float = fposmod(f * 127.1 + elapsed * (8.0 + fmod(f, 5.0) * 2.0), w)
        var y: float = fposmod(f * 93.73 + sin(elapsed * 0.27 + f * 1.6) * 17.0, h)
        var radius: float = 1.8 + fmod(f, 4.0) * 0.75
        draw_circle(Vector2(x, y), radius, Color(0.90, 0.78, 0.59, 0.10 if effect_level == 1 else 0.14))
