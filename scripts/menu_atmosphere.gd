extends Control

# Cosmetic particles displayed in the menu only (not yet world/map quality).
var effect_level: int = 1
var time_elapsed: float = 0.0

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_effect_level(level: int) -> void:
    effect_level = clampi(level, 0, 2)
    set_process(effect_level != 0)
    queue_redraw()

func _process(delta: float) -> void:
    time_elapsed += delta
    queue_redraw()

func _draw() -> void:
    if effect_level == 0:
        return
    var count := 26 if effect_level == 1 else 90
    var w := maxf(size.x, 1.0)
    var h := maxf(size.y, 1.0)
    for i in range(count):
        var f := float(i)
        var x := fposmod(f * 127.1 + time_elapsed * (10.0 + fmod(f, 6.0) * 1.8), w)
        var y := fposmod(f * 93.73 + sin(time_elapsed * 0.23 + f * 1.6) * 22.0, h)
        var radius := 2.7 + fmod(f, 5.0) * 0.75
        var opacity := 0.20 if effect_level == 1 else 0.28
        draw_circle(Vector2(x, y), radius, Color(0.93, 0.82, 0.63, opacity))
