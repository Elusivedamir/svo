extends Node

# Persistent music across splash and main menu. Do NOT mutate a GDScript const.
# Load after Godot's asset import: preload() may run before the OGG importer.
const TRACK_PATH: String = "res://assets/audio/frontline_evening_theme.ogg"
const SETTINGS_FILE: String = "user://settings.cfg"
var music: AudioStreamPlayer

func _ready() -> void:
    _restore_saved_volume()
    var resource: Resource = load(TRACK_PATH)
    if not (resource is AudioStreamOggVorbis):
        push_error("Cannot load menu soundtrack: " + TRACK_PATH)
        print("SMOKE_MUSIC_FAILED")
        return
    var track := resource as AudioStreamOggVorbis
    track.loop = true

    music = AudioStreamPlayer.new()
    music.name = "BackgroundMusic"
    music.stream = track
    music.bus = "Master"
    music.volume_db = -1.0
    add_child(music)
    music.play()
    print("SMOKE_MUSIC_STARTED: ", music.playing)

func _restore_saved_volume() -> void:
    var prefs := ConfigFile.new()
    var volume: float = 70.0
    if prefs.load(SETTINGS_FILE) == OK:
        volume = clampf(float(prefs.get_value("audio", "volume", 70.0)), 0.0, 100.0)
    AudioServer.set_bus_mute(0, volume <= 0.0)
    AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume / 100.0, 0.0001)))
