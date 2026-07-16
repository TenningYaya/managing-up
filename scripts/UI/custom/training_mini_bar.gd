# training_mini_bar.gd
# 培训面板头像底下的迷你属性条（自绘，无贴图）。三段配色：
#   天生自带    = 本色（效率蓝/品质金/经验绿）
#   往日培训所得 = 淡色（与员工面板同一个调亮系数，视觉一致）
#   本次培训所得 = 近纯白，一闪一闪（只在本面板出现；员工面板照旧全算淡色）
@tool   # 编辑器里也绘制：可以把它摆进任意场景实时预览（下面的导出值就是预览用数据）
extends Control
class_name TrainingMiniBar

const MAXV := 10          # 属性上限（条按 10 格比例画）
const BLINK_SPEED := 6.0  # 闪烁速度（越大越快）

@export var base_color: Color = Color("4fb2ff"):
	set(v): base_color = v; queue_redraw()
@export_range(0, 10) var total: int = 6:          # 当前属性总值
	set(v): total = v; queue_redraw()
@export_range(0, 10) var trained_total: int = 3:  # 所有培训点数（含本次）
	set(v): trained_total = v; queue_redraw()
@export_range(0, 10) var session: int = 2:        # 本次培训新增（白色闪烁段）
	set(v): session = v; queue_redraw()

## true = 员工面板那种圆角平滑条（无格子刻度）；false = 格子刻度条（培训面板头像下用的）
@export var smooth_style: bool = false:
	set(v): smooth_style = v; queue_redraw()
@export_range(0, 8) var corner_radius: int = 3:   # 平滑样式的圆角
	set(v): corner_radius = v; queue_redraw()

var _t := 0.0

func setup(color: Color, p_total: int, p_trained: int, p_session: int) -> void:
	base_color = color
	total = clampi(p_total, 0, MAXV)
	trained_total = clampi(p_trained, 0, total)
	session = clampi(p_session, 0, trained_total)
	queue_redraw()

func _process(dt: float) -> void:
	if session > 0:   # 只有存在闪烁段才每帧重绘，省性能
		_t += dt
		queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	if smooth_style:
		_draw_smooth(w, h)
		return
	# 深色描边（比条大一圈）：靠"局部对比"保证在任何浅色面板背景上都读得清
	draw_rect(Rect2(-1.0, -1.0, w + 2.0, h + 2.0), Color(0.06, 0.08, 0.1, 0.9))
	# 实色深底槽（没填满的部分 = 深灰蓝，和淡色段拉开对比）
	draw_rect(Rect2(0, 0, w, h), Color(0.16, 0.19, 0.23, 1.0))
	# 就地夹紧：编辑器里预览值随便乱填也不至于画出负宽矩形
	var t := clampi(total, 0, MAXV)
	var tr := clampi(trained_total, 0, t)
	var s := clampi(session, 0, tr)
	var innate := t - tr
	var past := tr - s
	var seg := w / float(MAXV)
	if innate > 0:
		draw_rect(Rect2(0, 0, seg * innate, h), base_color)
	if past > 0:
		draw_rect(Rect2(seg * innate, 0, seg * past, h), base_color.lightened(EmployeeAbility.TRAINED_LIGHTEN))
	if s > 0:
		# 近纯白 + 呼吸闪烁（alpha 0.5~1.0 来回）
		var c := Color.WHITE.lerp(base_color, 0.12)
		c.a = 0.5 + 0.5 * (0.5 + 0.5 * sin(_t * BLINK_SPEED))
		draw_rect(Rect2(seg * (innate + past), 0, seg * s, h), c)
	# 每格 1px 分隔线：读起来是"10 格刻度"，练了几点一眼可数，顺带进一步压住与背景的混淆
	for i in range(1, MAXV):
		draw_rect(Rect2(seg * i - 0.5, 0, 1.0, h), Color(0.06, 0.08, 0.1, 0.55))

# 员工面板样式：圆角平滑双色条（底槽 + 本色段 + 淡色段 + 白色闪烁段），无格子刻度。
# 画法和 EmployeeAbility 的"覆盖条"思路一致：先铺满值的淡色圆角条，再用本色圆角条盖住左边天生段。
func _draw_smooth(w: float, h: float) -> void:
	var t := clampi(total, 0, MAXV)
	var tr := clampi(trained_total, 0, t)
	var s := clampi(session, 0, tr)
	# 底槽：深色圆角 + 1px 描边（保住浅色背景上的可读性）
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.16, 0.19, 0.23, 1.0)
	bg.set_corner_radius_all(corner_radius)
	bg.set_border_width_all(1)
	bg.border_color = Color(0.06, 0.08, 0.1, 0.9)
	draw_style_box(bg, Rect2(0, 0, w, h))
	if t <= 0:
		return
	# 已填充总长（到 total），整条先铺淡色
	var fill_w := w * float(t) / float(MAXV)
	if tr > 0:
		draw_style_box(_fill_sb(base_color.lightened(EmployeeAbility.TRAINED_LIGHTEN)), Rect2(0, 0, fill_w, h))
	# 左段"天生"用本色盖回去
	var innate_w := w * float(t - tr) / float(MAXV)
	if t - tr > 0:
		draw_style_box(_fill_sb(base_color), Rect2(0, 0, innate_w, h))
	# 右端"本次收获"白色闪烁段
	if s > 0:
		var c := Color.WHITE.lerp(base_color, 0.12)
		c.a = 0.5 + 0.5 * (0.5 + 0.5 * sin(_t * BLINK_SPEED))
		var sx := w * float(t - s) / float(MAXV)
		draw_style_box(_fill_sb(c), Rect2(sx, 0, fill_w - sx, h))

func _fill_sb(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(corner_radius)
	return sb
