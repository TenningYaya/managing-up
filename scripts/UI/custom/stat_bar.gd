# stat_bar.gd
# 🌟 根节点直接继承 ProgressBar，完美保持原有物理结构
extends ProgressBar
class_name PropertyBar

@export_group("Visual Settings")
# 暴露颜色到 Inspector
@export var bar_color: Color = Color.WHITE:
	set(v):
		bar_color = v
		if is_node_ready():
			_apply_bar_color(bar_color)

@onready var value_label: Label = $AttributeNum

func _ready() -> void:
	# 🌟 以前这里是 progress_bar.xxx = 0，现在直接写 min_value，就是在对自己赋值！
	self.min_value = 0.0
	self.max_value = 10.0
	self.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# 初始化刷色
	_apply_bar_color(bar_color)

# 🌟 上游调用的函数名依然完美对接
func set_bar_value(val: float) -> void:
	# 🌟 给自己（ProgressBar）的 value 属性赋值
	self.value = val
	
	if value_label:
		value_label.text = str(int(val))

# 换色逻辑：同样是直接在自己身上操作 overrides
func _apply_bar_color(color: Color) -> void:
	# 🌟 直接从自己身上拿当前的 fill 样式
	var current_sb = self.get_theme_stylebox("fill")
	
	if current_sb is StyleBoxFlat:
		var new_sb = current_sb.duplicate()
		new_sb.bg_color = color
		self.add_theme_stylebox_override("fill", new_sb)
	else:
		var new_sb = StyleBoxFlat.new()
		new_sb.bg_color = color
		new_sb.set_corner_radius_all(5)
		self.add_theme_stylebox_override("fill", new_sb)
