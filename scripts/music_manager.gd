extends Node

# Persistent music player shared by the loading screen and main menu.
# The loop is an original, locally stored OGG file.
const MUSIC_STREAM: AudioStreamOggVorbis = preload("res://assets/audio/frontline_evening_theme.ogg")
const PREFS_PATH := "user://settings.cfg"

var player: AudioStreamPlayer
var gain: float = 70.0

func _ready() -> void:
    _load_volume()
    MUSIC_STREAM.loop = true
    player = AudioStreamPlayer.new()
    player.name = "BackgroundMusic"
    player.stream = MUSIC_STREAM
    player.bus = "Master"
    player.volume_db = -12.0
    add_child(player)
    _apply_volume()
    player.play()
    var fade_in := create_tween()
    fade_in.tween_property(player, "volume_db", 0.0, 1.2)

func _load_volume() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(PREFS_PATH) == OK:
        gain = clampf(float(cfg.get_value("audio", "volume", 70.0)), 0.0, 100.0)

func _apply_volume() -> void:
    AudioServer.set_bus_mute(0, gain <= 0.0)
    AudioServer.set_bus_volume_db(0, linear_to_db(maxf(gain / 100.0, 0.0001)))

func set_master_volume(value: float) -> void:
    gain = clampf(value, 0.0, 100.0)
    _apply_volume()
    ensure_playing()

func ensure_playing() -> void:
    if is_instance_valid(player) and not player.playing:
        player.play()

func replay_theme() -> void:
    ensure_playing()
    if is_instance_valid(player):
        player.volume_db = 0.0
        player.play(0.0)

func music_status() -> String:
    if gain <= 0.0:
        return "ЗВУК ВЫКЛЮЧЕН В ИГРЕ"
    if not is_instance_valid(player):
        return "ПРОИГРЫВАТЕЛЬ НЕ СОЗДАН"
    if player.playing:
        return "МЕЛОДИЯ ВОСПРОИЗВОДИТСЯ"
    return "МЕЛОДИЯ НЕ ЗАПУЩЕНА"
