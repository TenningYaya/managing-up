extends Control

@onready var texture_rect = $ScrollContainer/TextureRect
@onready var scroll_container = $ScrollContainer

func _ready() -> void:
	var tex = texture_rect.texture
	if tex:
		var ratio = tex.get_height() / float(tex.get_width())
		texture_rect.custom_minimum_size = Vector2(200, 200 * ratio)
	
	# 锁死 ScrollContainer 宽度
	scroll_container.custom_minimum_size.x = 200
	scroll_container.size.x = 200

func _process(delta: float) -> void:
	pass
