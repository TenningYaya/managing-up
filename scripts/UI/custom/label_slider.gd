# label_slider.gd
extends HBoxContainer
class_name EmployeeAbility

@export var ability_name: String = "属性名"

@onready var label: Label = $Label
# 修改这里的类型为 ProgressBar，并确保路径正确
@onready var progress_bar: ProgressBar = $ProgressBar 
@onready var value_label: Label = $ProgressBar/AttributeNum
#@onready var value_label_style = $ProgressBar/AttributeNumStyle

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
	progress_bar.value = val
	
	# 如果你的属性值是整数，用 str(int(val))
	# 如果需要保留一位小数，用 "%.1f" % val
	if value_label:
		value_label.text = str(int(val))
	#if value_label_style:
		#value_label_style.text = str(int(val))

func set_bar_color(color: Color) -> void:
	# 🌟 1. 先尝试获取当前已经在使用的 fill 样式
	# 如果你在编辑器里设置过 Style，这里就能拿回来
	var current_sb = progress_bar.get_theme_stylebox("fill")
	
	if current_sb is StyleBoxFlat:
		# 🌟 2. 核心：克隆一份一模一样的（包括圆角！）
		var new_sb = current_sb.duplicate()
		# 🌟 3. 只改颜色
		new_sb.bg_color = color
		# 🌟 4. 覆盖回去
		progress_bar.add_theme_stylebox_override("fill", new_sb)
	else:
		# 如果之前没设过样式，才需要新建（并手动补上圆角）
		var new_sb = StyleBoxFlat.new()
		new_sb.bg_color = color
		# 这里要手动设一下圆角，不然默认就是直角
		new_sb.set_corner_radius_all(5) 
		progress_bar.add_theme_stylebox_override("fill", new_sb)
