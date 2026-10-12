extends Node

# Survives LoadingScreen -> MainMenu. Master controls both music and later SFX.
const TRACK: AudioStreamOggVorbis = preload("res://assets/audio/frontline_evening_theme.ogg")
const SETTINGS_FILE: String = "user://settings.cfg"
var music: AudioStreamPlayer

func _ready() -> void:
    _restore_saved_volume()
    TRACK.loop = true
    music = AudioStreamPlayer.new()
    music.name = "BackgroundMusic"
    music.stream = TRACK
    music.bus = "Master"
    music.volume_db = -1.0
    add_child(music)
    music.play()
    print("SMOKE_MUSIC_STARTED: ", music.playing)

func _restore_saved_volume() -> void:
    var prefs := ConfigFile.new()
    var volume := 70.0
    if prefs.load(SETTINGS_FILE) == OK:
        volume = clampf(float(prefs.get_value("audio", "volume", 70.0)), 0.0, 100.0)
    AudioServer.set_bus_mute(0, volume <= 0.0)
    AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume / 100.0, 0.0001)))
