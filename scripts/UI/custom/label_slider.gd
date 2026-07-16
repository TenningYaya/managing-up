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
	label.text = tr(ability_name)  # ability_name 当作翻译 key 用
	
	# 设置 ProgressBar 的范围
	progress_bar.max_value = 10
	progress_bar.min_value = 0
	
	# ProgressBar 默认就不支持拖拽，但为了保险起见，
	# 我们可以让它不响应鼠标事件，防止遮挡底下的点击
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

# 语言切换时重刷属性名（ability_name 作为翻译 key）
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		label.text = tr(ability_name)

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
	_base_color = color
	_apply_colors()

# ==========================================
# 🌟 培训分色显示（只有员工面板调用；仓库等地方只调 set_value/set_bar_color，行为不变）
# 原理：主条整条填"培训亮色"，上面叠一条只填到 (总值-培训值) 的"本色"覆盖条 →
#       左段=本色（天生的），右段露出亮色（练出来的）。数字 Label 永远压在最上层。
# ==========================================
const TRAINED_LIGHTEN := 0.62   # 培训段颜色 = 本色调亮这么多（0~1，越大越浅/越淡）

var _base_color: Color = Color.WHITE
var _trained: int = 0
var _overlay: ProgressBar = null   # 覆盖条（懒创建：不用分色的界面根本不会生成它）

func set_trained_value(total: int, trained: int) -> void:
	set_value(total)
	_trained = clampi(trained, 0, total)
	if _trained > 0:
		_ensure_overlay()
	if _overlay:
		_overlay.max_value = progress_bar.max_value
		_overlay.min_value = progress_bar.min_value
		_overlay.value = float(total - _trained)
		_overlay.visible = _trained > 0
	_apply_colors()

func _ensure_overlay() -> void:
	if _overlay != null:
		return
	_overlay = ProgressBar.new()
	_overlay.show_percentage = false
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_theme_stylebox_override("background", StyleBoxEmpty.new())   # 背景透明，只画填充
	progress_bar.add_child(_overlay)
	progress_bar.move_child(_overlay, 0)   # 压在数字 Label 底下
	# ⚠️ 必须用 and_offsets 版本：只设锚点不清偏移的话，运行时新建的节点尺寸是 0，什么都画不出来
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

# 统一上色：分色时 主条=亮色 / 覆盖条=本色；不分色时 主条=本色
func _apply_colors() -> void:
	if _overlay != null and _overlay.visible:
		_set_fill(progress_bar, _base_color.lightened(TRAINED_LIGHTEN))
		_set_fill(_overlay, _base_color)
	else:
		_set_fill(progress_bar, _base_color)

# 给某条 ProgressBar 换填充色（克隆现有样式保住圆角；覆盖条克隆主条的样式保持外形一致）
func _set_fill(bar: ProgressBar, color: Color) -> void:
	var src = bar.get_theme_stylebox("fill")
	if not (src is StyleBoxFlat):
		src = progress_bar.get_theme_stylebox("fill")   # 覆盖条没样式时借主条的
	var new_sb: StyleBoxFlat
	if src is StyleBoxFlat:
		new_sb = src.duplicate()
	else:
		new_sb = StyleBoxFlat.new()
		new_sb.set_corner_radius_all(5)
	new_sb.bg_color = color
	bar.add_theme_stylebox_override("fill", new_sb)
