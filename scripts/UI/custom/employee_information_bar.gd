#employee_information_bar.gd
extends HBoxContainer

@onready var info_icon = $InfoIcon
@onready var info_label = $InfoLabel

# 🌟 暴露一个变量，让你在编辑器右侧直接选图
@export var icon_texture: Texture2D:
	set(val):
		icon_texture = val
		if is_node_ready():
			$InfoIcon.texture = val

func _ready():
	if icon_texture:
		$InfoIcon.texture = icon_texture

func set_value_text(text: String) -> void:
	info_label.text = text
