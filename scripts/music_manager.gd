extends Node

# One audio player survives LoadingScreen -> MainMenu transitions.
# All audio is original and shipped locally; no network permission required.
const TRACK: AudioStreamOggVorbis = preload("res://assets/audio/frontline_evening_theme.ogg")
const SETTINGS_FILE: String = "user://settings.cfg"
var music: AudioStreamPlayer

func _ready() -> void:
    _restore_saved_volume()
    TRACK.loop = true
    music = AudioStreamPlayer.new()
    music.stream = TRACK
    music.bus = "Master"
    music.volume_db = -27.0
    add_child(music)
    music.play()
    var start := create_tween()
    start.tween_property(music, "volume_db", -3.5, 3.0)

func _restore_saved_volume() -> void:
    var prefs := ConfigFile.new()
    if prefs.load(SETTINGS_FILE) == OK:
        var volume: float = clampf(float(prefs.get_value("audio", "volume", 70.0)), 0.0, 100.0)
        AudioServer.set_bus_mute(0, volume <= 0.0)
        AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume / 100.0, 0.0001)))
