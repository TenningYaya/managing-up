#label_slider.gd

extends HBoxContainer
class_name EmployeeAbility

# @export 让你可以在 Inspector 中直接填写文字
@export var ability_name: String = "属性名"

@onready var label: Label = $Label
@onready var slider: HSlider = $HSlider

func _ready() -> void:
	# 初始化时，将 Inspector 里填写的文字赋给 Label
	label.text = ability_name
	
	# 设置 Slider 的最大值为 10（根据你的 GDD 文档）
	slider.max_value = 10
	slider.min_value = 0
	
	# 关键：防止玩家用鼠标拖动进度条作弊
	slider.editable = false 
	slider.mouse_filter = Control.MOUSE_FILTER_IGNORE

# 面板主脚本调用这个函数来给 Slider 赋值
func set_value(val: int) -> void:
	slider.value = val
