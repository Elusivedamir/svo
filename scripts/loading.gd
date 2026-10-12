extends Control

const BG := preload("res://assets/loading_splash_ground.png")

var bg: TextureRect

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg = TextureRect.new()
	bg.texture = BG
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.offset_left = 0
	bg.offset_top = 0
	bg.offset_right = 0
	bg.offset_bottom = 0
	
	modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.45)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_instance_valid(bg):
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.offset_left = 0
		bg.offset_top = 0
		bg.offset_right = 0
		bg.offset_bottom = 0
