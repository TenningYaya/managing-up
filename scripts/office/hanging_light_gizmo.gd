@tool
extends Node2D
## 吊灯的【编辑器参考线框】—— 只在编辑器里画，不影响游戏。
##
## 运行时的光锥是由 IndoorLight 那块全屏遮罩统一画的（见 day_night.gd），
## 灯节点本身只提供"位置和宽度"。所以在编辑器里摆灯时看不见光，
## 这个脚本就是把【同一套公式】算出来的光锥轮廓画成线框，做到所见即所得。
##
## ⚠️ 它读的是 day_night.gd 里的常量本体，不是抄一份数字。
##    所以你改 LAMP_SPREAD / CONE_LEN / INSET，线框立刻跟着变，不会和运行时对不上。
##
## 根节点是 Node2D 而不是 TextureRect，是为了让【模板管大小、实例管位置】：
## Control 的位置和大小共用 offset_*，实例一覆盖位置就把大小也锁死了，
## 改模板宽度对已经摆好的灯不生效。换成 Node2D 之后实例只存 position 一个属性。

const DN = preload("res://scripts/system/day_night.gd")

const COLOR_CONE := Color(1.0, 0.85, 0.45, 0.55)  ## 光锥轮廓
const COLOR_EMIT := Color(1.0, 0.95, 0.70, 0.9)   ## 发光底边
const COLOR_CUT := Color(1.0, 0.35, 0.35, 0.7)    ## 被天花板线切掉的那段

@export var show_cone_gizmo: bool = true:
	set(v):
		show_cone_gizmo = v
		queue_redraw()

@onready var art: Control = $Art


func _ready() -> void:
	if Engine.is_editor_hint():
		# 位置变了也要重画 —— 只连 item_rect_changed 的话，拖动节点不会触发
		set_notify_transform(true)
		if art:
			art.item_rect_changed.connect(queue_redraw)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		queue_redraw()


## 办公区参考矩形 = indoor_light 遮罩。
## 编辑器里它还是你手摆的原始大小（代码铺大只发生在运行时），正好是我们要的基准。
func _ref_rect() -> Rect2:
	for m in get_tree().get_nodes_in_group(DN.INDOOR_GROUP):
		var c := m as Control
		if c != null:
			return c.get_global_rect()
	return Rect2()


func _draw() -> void:
	if not Engine.is_editor_hint() or not show_cone_gizmo:
		return
	var a := get_node_or_null("Art") as Control
	if a == null:
		return
	var ref := _ref_rect()
	if ref.size.x <= 0.0 or ref.size.y <= 0.0:
		return

	var lamp := a.get_global_rect()
	var cx: float = lamp.position.x + lamp.size.x * 0.5
	var hw0: float = lamp.size.x * 0.5 * (1.0 - DN.LAMP_LIGHT_INSET)

	# 发光底边（全局 y）。光锥从这里往下射。
	var emit_y: float = lamp.end.y + DN.LAMP_LIGHT_Y_OFFSET
	# 天花板线：这条线以上光一律不生效（挡窗户用的）
	var top_y: float = ref.position.y + DN.LAMP_LIGHT_TOP * ref.size.y
	var start_y: float = maxf(emit_y, top_y)
	var end_y: float = ref.end.y
	if end_y <= start_y:
		return

	# 半宽随深度线性张开，和 shader 里同一条公式
	var span: float = DN.LAMP_CONE_LEN * ref.size.y
	var hw := func(gy: float) -> float:
		var t: float = clampf((gy - emit_y) / maxf(span, 0.001), 0.0, 1.0)
		return hw0 + DN.LAMP_SPREAD * ref.size.x * t

	var w1: float = hw.call(start_y)
	var w2: float = hw.call(end_y)
	# 全局坐标算完再转回本地，这样节点被缩放/旋转也不会画歪
	var p1 := to_local(Vector2(cx - w1, start_y))
	var p2 := to_local(Vector2(cx + w1, start_y))
	var p3 := to_local(Vector2(cx + w2, end_y))
	var p4 := to_local(Vector2(cx - w2, end_y))

	draw_polyline(PackedVector2Array([p1, p4, p3, p2, p1]), COLOR_CONE, 2.0)

	# 发光底边标出来，方便判断"光是从灯罩哪儿出来的"
	draw_line(to_local(Vector2(cx - hw0, emit_y)),
			to_local(Vector2(cx + hw0, emit_y)), COLOR_EMIT, 3.0)

	# 灯挂在天花板线上方时，这一段光会被切掉 —— 画成红色，省得你以为参数没生效
	if emit_y < top_y:
		draw_line(to_local(Vector2(cx, emit_y)), to_local(Vector2(cx, top_y)), COLOR_CUT, 2.0)
