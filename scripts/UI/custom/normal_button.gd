#normal_button.gd
extends TextureButton

# 使用 @export 关键字，这样它就会出现在 Inspector 里
# 使用 setter (setget) 确保你在面板修改文字时，Label 能实时更新
@export var button_text: String = "InputButtonName":
	set(value):
		button_text = value
		# 确保节点已经准备就绪，防止在实例初始化时报错
		if is_inside_tree():
			$Label.text = value

func _ready() -> void:
	$Label.text = button_text
