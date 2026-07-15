# round_gauge.gd
# 培训轮数表盘：中间一个大数字(用子节点 Label 显示)，外面一圈粗线圆环。
# 底环粉色(整圈)，绿色从 12 点方向顺时针填充,代表【本轮】训练进度;每轮填满一次、归零重来。
# 不用任何贴图,draw_arc 直接画。挂在 TurnSelector 里、Minus 和 Plus 之间的一个 Control 上,
# 并给它加一个名为 "Label" 的子节点(居中、字体调大)当中间的数字。
@tool
extends Control
class_name RoundGauge

@export var ring_radius: float = 26.0:
	set(v): ring_radius = v; queue_redraw()
@export var ring_width: float = 6.0:
	set(v): ring_width = v; queue_redraw()
@export var color_bg: Color = Color("f48fb1"):    # 粉：底环
	set(v): color_bg = v; queue_redraw()
@export var color_fill: Color = Color("66bb6a"):  # 绿：本轮进度
	set(v): color_fill = v; queue_redraw()

var _progress: float = 0.0   # 0~1，本轮进度

@onready var _label: Label = get_node_or_null("Label")               # 中间的轮数数字
@onready var _progress_label: Label = get_node_or_null("ProgressLabel") # 本轮进度百分比

func _draw() -> void:
	var c := size / 2.0
	# 底环（粉，整圈）
	draw_arc(c, ring_radius, 0.0, TAU, 64, color_bg, ring_width, true)
	# 进度（绿，从 12 点方向顺时针延伸）
	if _progress > 0.0:
		var start := -PI / 2.0
		var end := start + TAU * clampf(_progress, 0.0, 1.0)
		draw_arc(c, ring_radius, start, end, 64, color_fill, ring_width, true)

# 面板每帧调用，喂本轮进度（0~1）
func set_progress(p: float) -> void:
	_progress = clampf(p, 0.0, 1.0)
	if _progress_label == null:
		_progress_label = get_node_or_null("ProgressLabel")
	if _progress_label:
		_progress_label.text = "%d%%" % roundi(_progress * 100.0)
	queue_redraw()

# 面板调用，设中间的数字（选择阶段=总轮数；进行中=剩余轮数）
func set_number(n: int) -> void:
	if _label == null:
		_label = get_node_or_null("Label")
	if _label:
		_label.text = str(n)

# 面板调用：进度百分比只在训练进行中显示，选择/结束时藏起来
func set_active(active: bool) -> void:
	if _progress_label == null:
		_progress_label = get_node_or_null("ProgressLabel")
	if _progress_label:
		_progress_label.visible = active
