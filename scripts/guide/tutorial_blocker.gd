# tutorial_blocker.gd
# 🌟 削权后的纯净版：只负责遮罩和挖洞，不写死任何逻辑！
#
# 实现从"四块 ColorRect 拼一个方洞"换成了"一张全屏 shader 遮罩"：
#   · 洞是圆角 + 柔边，不再是生硬直角方孔
#   · 切换目标时洞会平滑滑过去，而不是瞬间跳
#   · 洞口外缘有一圈会呼吸的光晕，正向强调目标（不只是压暗别人）
#   · 单张矩形，没有四块布拼缝处的亮线（原先要靠 round() 硬扛）
#
# ⚠️ 对外接口一个没变：_arrange_curtains() / hole_rect / is_hole_clickable / show-hide。
#    命中判定仍然只看 hole_rect 这个矩形，视觉再花哨也不影响点哪儿能点。
extends Control

# —— 外观参数（可在 Inspector 里调）——
@export var mask_color: Color = Color(0, 0, 0, 0.5)              # 幕布颜色
@export var corner_radius: float = 18.0                          # 洞的圆角半径
@export var edge_softness: float = 26.0                          # 洞口柔边宽度
@export var glow_color: Color = Color(1.0, 0.93, 0.65, 1.0)      # 洞口光晕颜色
@export var glow_width: float = 30.0                             # 光晕扩散宽度
@export var glow_strength: float = 0.55                          # 光晕亮度
@export var pulse_speed: float = 0.0                             # 光晕呼吸速度，0 = 静态不闪
@export var move_time: float = 0.28                              # 洞在目标之间滑动的时长
# 视为"同一个目标"的容差（像素）。教程为了跟住会动的目标是每帧调 _arrange_curtains 的，
# 位置只差一点点时必须【直接跟随】，否则每帧重启 tween 会把动画卡在起点、洞永远追不上。
@export var snap_threshold: float = 24.0

const SPOTLIGHT_SHADER := preload("res://data/shader/tutorial_spotlight.gdshader")

var hole_rect: Rect2 = Rect2()          # ← 命中判定唯一依据，保持原语义不变
var is_hole_clickable: bool = true

var _mask: ColorRect = null
var _mat: ShaderMaterial = null
var _move_tween: Tween = null
var _target_rect: Rect2 = Rect2()   # 当前动画正在滑向的目标，用来识别"是不是还是同一个目标"

# 洞的"视觉"位置与尺寸，与 hole_rect 分开：hole_rect 立刻生效（判定要准），
# 视觉这两个值则是被 tween 平滑过去的（好看）。setter 里同步写进 shader。
var _vis_pos: Vector2 = Vector2.ZERO:
	set(v):
		_vis_pos = v
		if _mat: _mat.set_shader_parameter("hole_position", v)
var _vis_size: Vector2 = Vector2.ZERO:
	set(v):
		_vis_size = v
		if _mat: _mat.set_shader_parameter("hole_size", v)


func _ready() -> void:
	# 游戏刚开局时，默默在后台把遮罩建好，然后隐身等总管召唤
	_create_mask()
	get_viewport().size_changed.connect(_fit_to_screen)
	hide()

# ==========================================
# 核心功能 1：建遮罩
# ==========================================
func _create_mask() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = SPOTLIGHT_SHADER

	_mask = ColorRect.new()
	_mask.name = "SpotlightMask"
	_mask.color = Color.WHITE          # 实际颜色由 shader 决定，这里只是给个底
	_mask.material = _mat
	_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 儿子不拦，老子拦
	add_child(_mask)

	_push_style()
	_fit_to_screen.call_deferred()

# 把 Inspector 里的外观参数一次性写进 shader
func _push_style() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("mask_color", mask_color)
	_mat.set_shader_parameter("corner_radius", corner_radius)
	_mat.set_shader_parameter("edge_softness", edge_softness)
	_mat.set_shader_parameter("glow_color", glow_color)
	_mat.set_shader_parameter("glow_width", glow_width)
	_mat.set_shader_parameter("glow_strength", glow_strength)
	_mat.set_shader_parameter("pulse_speed", pulse_speed)

# 遮罩永远铺满整个视口（窗口尺寸变化时自动跟上）
func _fit_to_screen() -> void:
	if _mask == null:
		return
	var vp := get_viewport_rect().size
	_mask.global_position = Vector2.ZERO
	_mask.size = vp
	if _mat:
		_mat.set_shader_parameter("rect_size", vp)

# ==========================================
# 核心功能 2：听从大总管的命令去挖洞
# ==========================================
func _arrange_curtains(rect: Rect2) -> void:
	# 🌟 像素对齐：窗口常是非整数缩放，取整让洞口落在整数像素上，边缘更干净
	rect = Rect2(rect.position.round(), rect.size.round())
	hole_rect = rect          # 判定立刻生效，不等动画
	_fit_to_screen()
	_push_style()             # 允许运行中改参数即时生效

	# 已经在往这个目标滑了（每帧重复下同一个指令）→ 什么都不做，让动画自己跑完。
	# 不加这一条的话，每帧 kill+重建 会让 tween 永远停在起点，洞根本滑不过去。
	if _move_tween and _move_tween.is_valid() and rect.is_equal_approx(_target_rect):
		return
	_target_rect = rect

	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()

	# 直接就位（不做动画）的几种情况：
	#   · 首次出现 / 遮罩没显示 / 传的是空矩形 → 别从屏幕角落滑过来
	#   · 目标只是轻微挪动（拖拽跟随、布局微调）→ 必须实时贴住，不能有延迟
	var moved := _vis_pos.distance_to(rect.position) + _vis_size.distance_to(rect.size)
	var instant := _vis_size == Vector2.ZERO or not visible or rect.size == Vector2.ZERO \
		or moved <= snap_threshold
	if instant:
		_vis_pos = rect.position
		_vis_size = rect.size
		return

	# 换到了另一个目标：平滑滑过去，像镜头重新对焦
	_move_tween = create_tween().set_parallel(true)
	_move_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_move_tween.tween_property(self, "_vis_pos", rect.position, move_time)
	_move_tween.tween_property(self, "_vis_size", rect.size, move_time)

# ==========================================
# 核心功能 3：负责物理拦截（逻辑与原来完全一致）
# ==========================================
func _has_point(point: Vector2) -> bool:
	if hole_rect == Rect2():
		return true # 没挖洞的时候，全屏拦死

	var global_mouse_pos = global_position + point

	# 如果鼠标点在了真空洞里
	if hole_rect.has_point(global_mouse_pos):
		# 如果大总管说这个洞可以点，就放行 (return false)；否则拦死 (return true)
		return not is_hole_clickable

	return true # 点在黑布上，必须拦死
