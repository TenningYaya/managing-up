# label_slider.gd
extends HBoxContainer
class_name EmployeeAbility

@export var ability_name: String = "属性名"

@onready var label: Label = $Label
# 修改这里的类型为 ProgressBar，并确保路径正确
@onready var progress_bar: ProgressBar = $ProgressBar 

func _ready() -> void:
	label.text = ability_name
	
	# 设置 ProgressBar 的范围
	progress_bar.max_value = 10
	progress_bar.min_value = 0
	
	# ProgressBar 默认就不支持拖拽，但为了保险起见，
	# 我们可以让它不响应鼠标事件，防止遮挡底下的点击
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

# 面板主脚本依然调用这个函数来赋值
func set_value(val: float) -> void:
	# ProgressBar 的 value 是 float 类型
	progress_bar.value = val

# --- 顺便把颜色换了的方法 ---
func set_bar_color(color: Color) -> void:
	# 通过代码修改 Theme Override 中的 fill 样式
	var sb = StyleBoxFlat.new()
	sb.bg_color = color
	# 给 ProgressBar 的 "fill" 样式设置新的颜色
	progress_bar.add_theme_stylebox_override("fill", sb)
