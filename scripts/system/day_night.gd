extends Node
## 昼夜变化（两态：白天 / 夜晚）
##
## 设计要点：
## 1. 【视觉周期和结算日解耦】Ledger.DAY_LENGTH 是"账目上的一天"，视觉周期单独一个
##    CYCLE_SECONDS，互不干涉。
## 2. 【渐变还是突变，由 Gradient 色标决定】色标挨得近 = 接近瞬间切换；
##    拉开 = 缓慢过渡。不用改代码，在编辑器里拖色标就行。
## 3. 【三层互不干扰】
##       屋里暗  ← CanvasModulate（乘法，只能压暗）  ← world_tint.tres
##       窗外蓝  ← sky_tint 的 shader（叠色）        ← sky_tint.tres
##       屋里亮  ← 加法混合的光层（只能提亮）        ← INDOOR_* 常数
##    天空 shader 里除掉了 CanvasModulate，所以调亮室内时窗外不会跟着亮。
##
## 接入方式（在编辑器里做一次）：
##   - 窗外那 6 张天空 TextureRect  → 分组 "sky_window"
##   - 室内开灯的光层（ColorRect 即可）→ 分组 "indoor_light"
##   - （以后）窗户亮灯的黄点图层    → 分组 "sky_window_lights"
##   CanvasModulate 会在运行时自动创建，不用你动场景。

const ENABLED := true                  ## 总开关，想关掉整套效果就改 false
const SKIP_DURING_TUTORIAL := true     ## 教程期间强制白天，免得新手一进来就摸黑

const CYCLE_SECONDS := 600.0           ## 一轮昼夜多少秒
## 起始偏移。Gradient 的 phase 0 是深夜，而 total_time 从 0 起算，
## 不偏移的话新档一进游戏就是黑的。0.5 = 从正午开场。
const PHASE_OFFSET := 0.5

const SKY_GROUP := "sky_window"            ## 窗外天空贴图
const AUTO_FIND_SKY := false                ## 组是空的就按场景结构自己找天空图补进去
const SKY_PARENT_NAME := "RightCover"      ## 天空图挂在谁下面
const LIGHTS_GROUP := "sky_window_lights"  ## 夜晚窗户亮灯叠加层（黄点，你自己画）

## ── 窗户夜景叠层 ──────────────────────────────────────────────
## 从下往上：白天原图 → 夜景图（淡入淡出）→ 光晕 → 亮框。
## 子节点天生画在父节点之上，添加顺序就是层序，不用管 z_index。
##
## ⚠️ 这里【没有】叠色蒙版。早先那版是拿 shader 往原图上混深蓝，结果是发灰 ——
##    因为乘法/混色只能把原图的颜色搅浑，做不出"另一个时段的画"。
##    换成直接交叉淡化到你画好的夜景图，颜色就是你画的颜色。
##    sky_tint.gdshader 现在没人用了，留着没坏处，想删随时删。
const WINDOW_NIGHT_PATH := "res://assets/background/glass_wall_night.png"
const WINDOW_GLOW_PATH := "res://assets/background/glass_wall_lighting.png"
const WINDOW_FRAME_PATH := "res://assets/background/glass_wall_frame.png"
const WINDOW_NIGHT_NODE := "_DayNightView"
const WINDOW_GLOW_NODE := "_DayNightGlow"
const WINDOW_FRAME_NODE := "_DayNightFrame"
## 开灯是个【事件】，不是渐变 —— 所以用阈值触发再淡入，而不是跟着夜色线性爬。
## 天黑到 GLOW_ON_AT 这个程度，窗灯才开始亮，花 GLOW_FADE_SEC 秒淡入；天亮时同样淡出。
const GLOW_ON_AT := 0.5           ## night_amount 超过多少算"够黑了"
const GLOW_FADE_SEC := 1.5        ## 淡入淡出用几秒（现实时间，不受游戏倍速影响）

## 亮框和光晕豁免全局压暗。
## CanvasModulate 压的是整个世界画布，你的图也在里面，所以会跟桌椅一起被摁暗一半。
## 这里乘上 1/压暗色 抵消掉，净效果 = 完全按你 Procreate 里画的样子显示。
## 关掉的话它俩就会跟着天一起黑 —— 那样"亮着的灯"就不成立了。
const WINDOW_IGNORE_NIGHT := true
const INDOOR_GROUP := "indoor_light"       ## 室内"开灯"光层（加法混合）

const WORLD_GRADIENT: Gradient = preload("res://data/daynight/world_tint.tres")
## 现在它只剩一个职责：用 Alpha 画出"夜的浓度曲线"（RGB 不再有人读）。
## 峰值会在 _ready 里自动量出来归一化，所以你随便拖 Alpha，不用再去同步任何常量。
const SKY_GRADIENT: Gradient = preload("res://data/daynight/sky_tint.tres")

## ── 吊顶灯 ──────────────────────────────────────────────────
## 天花板降下 N 盏横灯管，每盏往下打一个梯形光锥。锥内正常亮，锥外压暗靛蓝，
## 【锥与锥之间的缝隙】才是表现夜晚的地方。
##
## 用乘法遮罩而不是加法光：加法是往黑画面上糊暖色，怎么调都发闷；
## 乘法是锥内乘 1（画面原样 = 真正的"正常亮度"）、锥外乘暗色。
const INDOOR_SHADER: Shader = preload("res://data/shader/ceiling_lamp.gdshader")
## ⚠️ 这四个是【乘数】，而且【必须 ≤ 1】。
##    2D 画布是 8 位定点混合，着色器输出会先被 clamp 到 [0,1] 再相乘，
##    所以填 2.5 实际生效的是 1.0 —— 想靠乘法把压暗的画面"提亮回去"是做不到的。
##    唯一可行的模型是：【暗是减出来的，亮是"没被减"】。
##    灯下乘 1 = 原图分毫不动 = 真正的正常亮度；灯外乘 0.4 = 压暗。
## ── 夜幕是【纵向渐变】的，不是一个固定颜色 ──
## 夜色从窗户渗进来：靠窗那头最蓝最暗，越往屋里越淡，底部几乎不压暗。
## 这样不用专门去画两锥之间那块楔形 —— 它露出来的就是这条渐变，
## 天然"下面亮、往上渐渐发蓝"。
const LAMP_DARK_TOP := Color(0.534, 0.616, 0.798)   ## 贴着窗户那头
const LAMP_DARK_BOTTOM := Color(0.97, 0.98, 1.0)    ## 屋子深处，几乎不压暗
## 蓝色【最深】的那条线在哪。0 = 天花板，正数往下挪，负数往上提（进玻璃带）。
## 换算：1.0 = 办公区整高 ≈ 362 像素，所以 0.1 ≈ 36 像素。
## 你要的：画面下半截全白、50%~80% 高度之间过渡、80% 以上全蓝。
## ry 是从办公区【上沿】往下算的（0 = 天花板，1 = 下沿），所以换算过来：
##   80% 高度 = ry 0.2（这条线以上全蓝）
##   50% 高度 = ry 0.5（这条线以下全白）
const LAMP_DARK_START := -0.05
const LAMP_DARK_SPAN := 0.1    ## 从那条线往下渐变多高，到这儿蓝色消失
## ⚠️ >1 = 蓝的范围【变大】（我之前注释写反了，你设成 2.0 等于让蓝更多）。1.0 = 线性。
const LAMP_DARK_POWER := 1.0

## 调试：把夜幕渐变画成 绿→红 的色带，看清那两条线到底落在哪。
## 纯绿 = 全蓝区，纯红 = 全白区，中间是过渡带。调完改回 false。
const LAMP_DEBUG_GRADIENT := false
const LAMP_LIT := Color(1.00, 1.00, 1.00)     ## 一盏灯照到：什么都不做 = 原图亮度
const LAMP_OVERLAP := Color(0.97, 0.99, 1.00) ## 两锥交叠：几乎不动，暖色交给加法层

## ── 加法层：只负责"亮" ──────────────────────────────────────
## 乘法最多做到"原图亮度"，做不出【比原图更亮】，所以灯下看着只是白天的颜色，
## 没有"被照亮"的感觉。这一层补上那一截。
## 而且它【只在光锥内出数】，锥外加 0 —— 所以不会像早先那版一样把暗部一起抬亮糊成一片。
##
## 数值要小。0.10 已经是很明显的"被照亮"，上到 0.3 开始过曝。
## 调色：三个分量一起加 = 更亮；把 B 压低 = 更黄。
## 「很淡的亮黄」= 三个都不低 + B 稍低。R/G 高而 B 接近 0 那是纯黄，会很脏。
const LAMP_LIT_ADD := Color(0.040, 0.055, 0.130)    ## 一盏灯照到：加一点暖光
const LAMP_OVERLAP_ADD := Color(0.140, 0.170, 0.260) ## 两锥交叠：更亮的淡黄
const LAMP_ADD_SHADER: Shader = preload("res://data/shader/ceiling_lamp_add.gdshader")
const LAMP_ADD_NODE := "_LampGlowAdd"

## 遮罩往四周铺多少像素。铺大是为了盖住整个可见画面 —— 夜色全靠这块布，
## 布的边缘就是"夜晚的边缘"，所以宁可铺大。
## 灯的位置由 ref_min/ref_size 换算，铺多大都不会把灯带跑，放心加。
const MASK_PAD_X := 3000.0
const MASK_PAD_TOP := 1200.0
const MASK_PAD_BOTTOM := 1200.0
## ── 灯的位置来自场景节点，不是常量 ───────────────────────────
## 把 hanging_light.tscn 拖进办公室，随便摆、随便缩放，光锥自动跟着走。
## 想加一盏就再拖一个，上限 8 盏（shader 数组大小）。
## 原先那套 LAMP_COUNT / PITCH / HALF_W / GROUP_X / Y_UP / Y_DOWN 全部作废 ——
## 位置信息现在在场景里，所见即所得，不用跑游戏对数字。
const LAMP_GROUP := "ceiling_lamp"
const LAMP_MAX := 8

## 发光部分比灯的图窄多少（每边）。你说"横向往里收了一点点"，就是这个。
## 0.08 = 两边各收 8%，光锥不会从灯罩最外沿直接射出来。
const LAMP_LIGHT_INSET := 0.08

## 光柱起点相对灯【底边】上下挪多少像素。正数 = 光往下挪（灯和光之间留空），
## 负数 = 光往上提（钻进灯罩里）。灯的图本身不动，只动光。
const LAMP_LIGHT_Y_OFFSET := 0.0

## 灯【自身】发亮的那一截，占灯图高度的比例，从底边往上算。
## 只算下面一截是因为你的图上半部分是锁链 —— 链条不该发光。
## 高度减半过了（原来 0.35）。底边不动，只往上收。
const LAMP_CORE_FRAC := 0.175
## 灯芯是【圆角矩形 + 柔边】，不是硬方块 —— 真光源的边界一定是糊的。
const LAMP_CORE_ROUND := 0.8    ## 1 = 两头全圆（胶囊形）
const LAMP_CORE_SOFT := 0.05    ## 柔边往外化开多少（办公区高度的倍数）
const LAMP_CORE_POWER := 1.4    ## 柔边衰减曲线。越大越贴着灯管
## 灯芯的强光。整套里最亮的一处 —— 它是光源，得比它照亮的东西更亮。
const LAMP_CORE_ADD := Color(0.360, 0.390, 0.450)

## "降下来"的幅度：天亮时灯缩到这么高的上方，天黑时滑回原位。
## 跟窗灯同一条 1.5 秒曲线。设 0 = 不要这个动画。
const LAMP_DESCEND_PX := 70.0

## 灯的图画在夜色遮罩【之上】，所以完全不被压暗，原样显示。
## 遮罩自己是 INDOOR_LIGHT_Z（100），所以这里要更高。
const LAMP_ART_Z := 110
## 加法层再往上一层，这样光晕/灯芯能盖在灯的图上面 —— 否则光被图挡住，
## 灯管那块柔光就只能从边缘漏一点出来，等于白做。
## 这是相对遮罩的增量（遮罩 100 + 20 = 120）。
const LAMP_GLOW_Z := 20

const LAMP_SPREAD := 0.46             ## 梯形往下张开多少。0 = 直筒，越大越像喇叭
const LAMP_CONE_LEN := 10.0            ## 光打多远（1 = 直到办公区底部）


## 硬边斜线按屏幕像素走的话，台阶会比美术本身的像素还细，看着像锯齿而不像设计。
## 填你的美术放大倍率（一个美术像素 = 几个屏幕像素），台阶就和像素块同尺寸。1 = 不对齐。
const LAMP_BLOCK_PX := 1.0

## 光的上边界。这条线以上【一律不受光】，哪怕光锥罩到了。
## 用来挡住窗户 —— 室内吊灯照不到室外，但遮罩分不清室内室外，不设这条线的话
## 光锥会在窗户上"挖个洞"，露出白天的玻璃贴图。
## 0 = 你手摆那个遮罩矩形的上沿 = 办公室天花板。正数往下挪，负数往上放。
const LAMP_LIGHT_TOP := -20

## ── 灯管周围的光晕 ──
## 和光锥是两回事：光锥是"照到哪儿"，光晕是"灯本身在发光"，四面八方都有。
## 它会溢到光锥之外的暗区里 —— 那正是"雾状扩散"的来源。
##
## ⚠️ LAMP_GLOW_STEPS 是重点：像素风的光晕是【一圈圈硬边色阶】，不是平滑渐变。
##    平滑渐变在像素画里会糊成一团脏东西 —— 你上次觉得"还不如没有"多半就是这个原因。
##    2~4 圈最常见，越少越硬朗。
## ⚠️ 这个值要【小】。灯管是条长线段，光晕是贴着它的胶囊形，
##    半径一大，每圈在中段就是一条笔直的横线 —— 看着不像光晕，像凭空画了条分界线。
##    参考：0.10 ≈ 36 像素，而灯管才 7 像素粗，这个比例看着还像"灯周围"。
##    超过 0.2 就开始变成一条横贯办公室的光带了。
const LAMP_GLOW_RADIUS := 0.25                   ## 扩散多远（参考矩形高度的倍数）
const LAMP_GLOW_POWER := 2.2                     ## 衰减曲线。越大越集中在灯管附近
const LAMP_GLOW_STRETCH := 1.0                   ## >1 横向拉长成椭圆
## 0 = 平滑模糊（柔光晕）；≥2 = 量化成那么多圈硬边色阶。
## 之前那条莫名其妙的横线就是色阶造成的 —— 灯管是长线段，每圈在中段都是平的。
const LAMP_GLOW_STEPS := 0.0
const LAMP_GLOW_ADD := Color(0.090, 0.110, 0.150)



## ── 纵向衰减 ──
## 光越往下越弱。【只作用在加法层】—— 乘法层照旧灯下乘 1，
## 所以灯下仍然是正常亮度，衰减掉的只是额外叠上去的那层光。
## 这么分的好处：衰减再狠也不会把桌椅人物压暗，只是"光没那么浓"。
const LAMP_FADE_DIST := 1.0    ## 衰减跨度。1.0 = 从灯管一路衰减到办公区底部
const LAMP_FADE_MIN := 0    ## 最远处还剩多少光。0 = 完全没有
const LAMP_FADE_POWER := 0.8   ## 曲线。>1 = 亮区更集中在顶部；<1 = 衰减得更慢

## 光层节点自动生成，不用你去 main.tscn 里摆。
## 横向范围和上沿【自动对齐天空带】——正好从那条天空下面开始，不会照到窗外。
## 如果你想自己摆，就在场景里放个节点加进 "indoor_light" 组，代码检测到就不再自动生成。
const INDOOR_AUTO_CREATE := true
const INDOOR_LIGHT_TEX: Texture2D = preload("res://data/daynight/indoor_light_gradient.tres")
const INDOOR_LIGHT_HEIGHT := 420.0    ## 光往下照多远
const INDOOR_LIGHT_TOP_BIAS := 0.0    ## 上沿微调，正数往下挪
const INDOOR_LIGHT_Z := 100           ## 要盖在员工/家具上面才照得到它们
const INDOOR_FORCE_Z := true          ## 连手摆的光层也强制顶到 INDOOR_LIGHT_Z
const FALLBACK_SKY_BAND_H := 26.0     ## 天空没加组时的兜底：Floors 顶部往下让开多少

## 打开后每秒往输出面板打一行状态，用来定位"为什么看不见光"。调完记得关。
const DEBUG_LOG := true

## 窗户亮灯图层的亮度补偿。CanvasModulate 会把整个世界一起压暗，
## 想让窗户"发光"就得补回来。>1 是允许的，Godot 会真的提亮。
const LIGHTS_BOOST := 1.9

var phase: float = 0.0        ## 当前昼夜进度 0~1，别处想读"现在几点"用这个
## 调试用的进度偏移。跳转昼夜时只动它，【不碰 Gamemanager.total_time】——
## total_time 是全局游戏时长，账目结算之类的东西都挂在上面，为了看个夜景去改它会出乱子。
var phase_shift: float = 0.0
var night_amount: float = 0.0 ## 0 = 大白天，1 = 全黑。给别的系统当钩子用

var debug_phase: float = -1.0 ## ≥0 时锁定进度，方便调色；-1 = 跟随时间

var _add_mat: ShaderMaterial    ## 乘法层：只压暗
var _glow_mat: ShaderMaterial   ## 加法层：只提亮
var _canvas_mod: CanvasModulate = null
var _auto_light: TextureRect = null   ## 自动生成的那个光层，只有它才走自动对齐
var _warned_no_sky := false
var _indoor_orig: Dictionary = {}   ## 手摆遮罩的原始矩形，上拉时作基准，防止每帧累加
var _ref_min := Vector2.ZERO        ## 办公区参考矩形在铺大后的遮罩里的起点（UV）
var _ref_size := Vector2.ONE
var _ref_global := Rect2()          ## 参考矩形的全局位置，换算灯的坐标用
var _lamps: PackedVector4Array = []  ## 每盏灯：x=中心 y=底边 z=半宽（ruv 空间）
var _lamp_orig: Dictionary = {}     ## 灯的原始位置，"降下来"动画的基准
var _ref_aspect := 1.0              ## 参考矩形宽高比，用来把光晕修圆        ## 同上，尺寸。灯的坐标全部相对它算
var _debug_timer := 0
var _last_sky_count := -1
var _dt := 0.0
var _glow_a := 0.0     ## 窗灯当前透明度，阈值触发后往目标值慢慢挪

var _overlay_ready := false
var _night_tex: Texture2D
var _frame_tex: Texture2D
var _glow_tex: Texture2D
var _comp := Vector3.ONE    ## 抵消全局压暗用的倍数
var _night_src := Rect2()   ## 夜景图在它自己画布上的内容框
var _frame_src := Rect2()   ## 亮框的内容框 = 窗口本体，其余两层都以它为基准对齐
var _glow_src := Rect2()    ## 光晕的内容框，比窗口大一圈
var _night_peak := 1.0      ## 夜色曲线的 Alpha 峰值，用来归一化


func _ready() -> void:
	_add_mat = ShaderMaterial.new()
	_add_mat.shader = INDOOR_SHADER
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = LAMP_ADD_SHADER

	# 量出夜色曲线的 Alpha 峰值，让"峰值 = 完全入夜"。
	# 这样你在编辑器里随便拖 Alpha，都不用再回来同步某个常量 —— 之前那个手动同步
	# 是个纯粹的坑，改一边忘另一边，窗灯时机和室内亮度就会莫名其妙偏掉。
	_night_peak = 0.001
	for i in SKY_GRADIENT.get_point_count():
		_night_peak = maxf(_night_peak, SKY_GRADIENT.get_color(i).a)


func _process(_delta: float) -> void:
	if not ENABLED:
		return

	_dt = _delta

	if SKIP_DURING_TUTORIAL and not Gamemanager.is_tutorial_completed:
		_apply(_day_phase())
		return

	phase = fposmod(Gamemanager.total_time / CYCLE_SECONDS + PHASE_OFFSET + phase_shift, 1.0)
	_apply(debug_phase if debug_phase >= 0.0 else phase)


func _apply(p: float) -> void:
	var world: Color = WORLD_GRADIENT.sample(p)
	# 曲线的 Alpha 只画形状，峰值当作"完全入夜"。除以峰值归一化成 0~1。
	night_amount = clampf(SKY_GRADIENT.sample(p).a / _night_peak, 0.0, 1.0)

	# ── 屋里：整体压暗 ──
	var cm := _get_canvas_modulate()
	if cm:
		cm.color = world

	_ensure_sky_group()

	# 窗灯的淡入淡出。每帧一次，不是每个节点一次 —— 12 张窗要同步亮。
	var glow_target: float = 1.0 if night_amount >= GLOW_ON_AT else 0.0
	_glow_a = move_toward(_glow_a, glow_target, _dt / maxf(GLOW_FADE_SEC, 0.001))

	# 抵消全局压暗。乘 1/压暗色，CanvasModulate 再乘回来正好是 1，等于原样显示。
	_comp = Vector3.ONE
	if WINDOW_IGNORE_NIGHT:
		_comp = Vector3(
			1.0 / maxf(world.r, 0.001),
			1.0 / maxf(world.g, 0.001),
			1.0 / maxf(world.b, 0.001))

	for n in get_tree().get_nodes_in_group(SKY_GROUP):
		var ci := n as CanvasItem
		if ci and ci.material != null:
			ci.material = null   # 清掉早先那版叠色 shader 留下的材质
		var tr := n as TextureRect
		if tr:
			_ensure_window_overlays(tr)
			_update_window_overlays(tr)

	# ── 吊顶灯 ──
	_ensure_indoor_light()
	_layout_indoor_light()
	# 整套效果（包括灯降下来）都跟 _glow_a 走，和窗灯同一时刻、同一条曲线。
	var lit: float = _glow_a
	# 两层必须吃完全一样的几何参数，否则光锥的暗边和亮边会错开一截
	_update_lamps(lit)
	_set_lamp_geometry(_add_mat, lit)
	_set_lamp_geometry(_glow_mat, lit)

	# 乘法层：只管暗
	_add_mat.set_shader_parameter("dark_top", _v3(LAMP_DARK_TOP))
	_add_mat.set_shader_parameter("dark_bottom", _v3(LAMP_DARK_BOTTOM))
	_add_mat.set_shader_parameter("lamp_color", _v3(LAMP_LIT))
	_add_mat.set_shader_parameter("overlap_color", _v3(LAMP_OVERLAP))

	# 加法层：只管亮
	_glow_mat.set_shader_parameter("lit_add", _v3(LAMP_LIT_ADD))
	_glow_mat.set_shader_parameter("overlap_add", _v3(LAMP_OVERLAP_ADD))
	_glow_mat.set_shader_parameter("glow_add", _v3(LAMP_GLOW_ADD))
	_glow_mat.set_shader_parameter("core_add", _v3(LAMP_CORE_ADD))
	_glow_mat.set_shader_parameter("fade_dist", LAMP_FADE_DIST)
	_glow_mat.set_shader_parameter("fade_min", LAMP_FADE_MIN)
	_glow_mat.set_shader_parameter("fade_power", LAMP_FADE_POWER)

	for n in get_tree().get_nodes_in_group(INDOOR_GROUP):
		var ci := n as CanvasItem
		if ci:
			if ci.material != _add_mat:
				ci.material = _add_mat
				# 光层盖在所有东西上面，不设 IGNORE 会把点击全吃掉（ColorRect 默认是 STOP）
				if ci is Control:
					(ci as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
			# 手摆的节点 z_index 默认是 0，会被办公室内容压在下面 —— 统一顶上去。
			# 不想被接管就把 INDOOR_FORCE_Z 关掉，自己在场景里调。
			if INDOOR_FORCE_Z and ci.z_index != INDOOR_LIGHT_Z:
				ci.z_index = INDOOR_LIGHT_Z
			ci.modulate = Color.WHITE   # 颜色交给 shader，这里别再乘一遍
			ci.visible = lit > 0.001
			if ci != _auto_light:
				_pad_indoor_mask(ci as Control)
				_ensure_glow_layer(ci as Control)

	# ── 窗户亮灯：透明度直接跟"夜的强度"走 ──
	for n in get_tree().get_nodes_in_group(LIGHTS_GROUP):
		var ci := n as CanvasItem
		if ci:
			ci.modulate = Color(LIGHTS_BOOST, LIGHTS_BOOST, LIGHTS_BOOST, night_amount)

	if DEBUG_LOG:
		_debug_tick(p, world, lit)


## ── 调试：昼夜跳转 ────────────────────────────────────────────
## 跳到【灯刚好要开/要关的那一刻】，按下去立刻就能看见变化。
##
## 这两个点是从曲线里【算】出来的，不是手填的 —— 你在编辑器里拖色标之后，
## 跳转点自动跟着走。之前写死 0.70 / 0.16，你一改曲线就对不上，按了像没反应。
func _night_at(p: float) -> float:
	return clampf(SKY_GRADIENT.sample(p).a / _night_peak, 0.0, 1.0)


## 扫一遍曲线，找 night_amount 穿过开灯阈值的那个进度。
## rising = true 找天黑那次，false 找天亮那次。
func _find_crossing(rising: bool) -> float:
	const STEPS := 400
	var prev: float = _night_at(0.0)
	for i in range(1, STEPS + 1):
		var p: float = float(i) / float(STEPS)
		var cur: float = _night_at(p)
		if rising and prev < GLOW_ON_AT and cur >= GLOW_ON_AT:
			return p
		if not rising and prev >= GLOW_ON_AT and cur < GLOW_ON_AT:
			return p
		prev = cur
	return 0.75 if rising else 0.25   # 曲线没有穿越点时的兜底


## 把当前进度挪到 target，之后照常往前走（不是锁定）。
func jump_to_phase(target: float) -> void:
	var base: float = fposmod(Gamemanager.total_time / CYCLE_SECONDS + PHASE_OFFSET, 1.0)
	phase_shift = fposmod(target - base, 1.0)


## 在天黑和天亮之间来回跳。返回 true = 跳去天黑。
func debug_toggle_daynight() -> bool:
	var to_night: bool = night_amount < GLOW_ON_AT
	var target: float = _find_crossing(to_night)
	jump_to_phase(target)
	# 立刻把状态推到位，省得按钮文字和日志还停在旧值上
	_apply(target)
	print("[DayNight] 跳到 %s，phase=%.3f" % ["天黑" if to_night else "天亮", target])
	return to_night


func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


## 乘法层和加法层共用同一套形状参数。写成一个函数，省得改参数要改两遍 ——
## 两边一旦不同步，光锥的暗边和亮边就会错开一截，而且极难查。
func _set_lamp_geometry(mat: ShaderMaterial, lit: float) -> void:
	mat.set_shader_parameter("amount", lit)
	mat.set_shader_parameter("lamp_n", _lamps.size())
	mat.set_shader_parameter("lamps", _lamps)
	mat.set_shader_parameter("spread", LAMP_SPREAD)
	mat.set_shader_parameter("cone_len", LAMP_CONE_LEN)
	mat.set_shader_parameter("light_top", LAMP_LIGHT_TOP)
	mat.set_shader_parameter("dark_start", LAMP_DARK_START)
	mat.set_shader_parameter("dark_span", LAMP_DARK_SPAN)
	mat.set_shader_parameter("dark_power", LAMP_DARK_POWER)
	mat.set_shader_parameter("debug_gradient", LAMP_DEBUG_GRADIENT)
	mat.set_shader_parameter("core_frac", LAMP_CORE_FRAC)
	mat.set_shader_parameter("core_round", LAMP_CORE_ROUND)
	mat.set_shader_parameter("core_soft", LAMP_CORE_SOFT)
	mat.set_shader_parameter("core_power", LAMP_CORE_POWER)
	mat.set_shader_parameter("block_px", LAMP_BLOCK_PX)
	mat.set_shader_parameter("glow_radius", LAMP_GLOW_RADIUS)
	mat.set_shader_parameter("glow_power", LAMP_GLOW_POWER)
	mat.set_shader_parameter("glow_stretch", LAMP_GLOW_STRETCH)
	mat.set_shader_parameter("glow_steps", LAMP_GLOW_STEPS)
	mat.set_shader_parameter("ref_aspect", _ref_aspect)
	# 遮罩铺得比办公区大，这两个把灯的坐标锁回原始矩形
	mat.set_shader_parameter("ref_min", _ref_min)
	mat.set_shader_parameter("ref_size", _ref_size)


## 扫一遍场景里的灯，把每盏的位置换算成 shader 要的 ruv 坐标。
##
## 灯是 Control，所以直接读 get_global_rect()：
##   x = 横向中心、y = 【底边】（光从底边出，锁链在上面天然不参与）、z = 半宽。
## 这意味着你在编辑器里怎么摆、缩放到多大，光锥都自动跟上，不用改任何数字。
func _update_lamps(lit: float) -> void:
	_lamps.clear()
	var raw: Array[Vector4] = []
	if _ref_global.size.x <= 0.0 or _ref_global.size.y <= 0.0:
		return   # 遮罩还没量出来，这一帧先跳过

	var lift: float = (1.0 - lit) * LAMP_DESCEND_PX   # 天亮时缩到上方
	for n in get_tree().get_nodes_in_group(LAMP_GROUP):
		var c := n as CanvasItem
		if c == null:
			continue

		# 记住原位，否则每帧在上一帧基础上再抬一次，灯会一路飞走
		var key := c.get_instance_id()
		if not _lamp_orig.has(key):
			_lamp_orig[key] = c.get("position")
		var home: Vector2 = _lamp_orig[key]
		c.set("position", Vector2(home.x, home.y - lift))
		c.visible = lit > 0.001
		c.z_index = LAMP_ART_Z   # 画在夜色遮罩之上 = 不被压暗

		if _lamps.size() >= LAMP_MAX:
			continue   # 超出 shader 数组上限的灯只摆不发光
		var r := _lamp_rect(c)
		if r.size.x <= 0.0:
			continue
		raw.append(Vector4(
			(r.position.x + r.size.x * 0.5 - _ref_global.position.x) / _ref_global.size.x,
			(r.end.y + LAMP_LIGHT_Y_OFFSET - _ref_global.position.y) / _ref_global.size.y,
			r.size.x * 0.5 * (1.0 - LAMP_LIGHT_INSET) / _ref_global.size.x,
			r.size.y / _ref_global.size.y))   # w = 灯图的高，灯芯要用

	# 按 x 从左到右排好 —— 楔形算的是"相邻两盏"的关系，
	# 场景里的节点顺序不保证和左右顺序一致，不排的话会把不相邻的两盏配成一对。
	raw.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.x < b.x)
	for v in raw:
		_lamps.append(v)


## 灯的实际占地矩形。
## 灯的根节点是 Node2D（为了让"模板管大小、实例管位置"成立），
## 图在它下面的 Art 子节点上，所以尺寸要去子节点上拿。
## 根节点直接是 Control 的老结构也兼容。
func _lamp_rect(n: CanvasItem) -> Rect2:
	if n is Control:
		return (n as Control).get_global_rect()
	for ch in n.get_children():
		var c := ch as Control
		if c != null:
			return c.get_global_rect()
	return Rect2()


## 加法层挂成乘法层的【子节点】：子节点天生画在父节点之后，所以
## 「先压暗、再加光」的顺序自动就对；尺寸用 FULL_RECT 跟着父节点走，
## 两层的 UV 空间永远一致，不用另外同步位置和大小。
func _ensure_glow_layer(host: Control) -> void:
	if host == null or host.has_node(LAMP_ADD_NODE):
		return
	var g := ColorRect.new()
	g.name = LAMP_ADD_NODE
	# 默认透明。ColorRect 默认是白色不透明，万一 shader 编译失败退回默认材质，
	# 这块铺满全屏的布会把整个画面刷白 —— 留个保险。
	g.color = Color(0, 0, 0, 0)
	g.material = _glow_mat
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.set_anchors_preset(Control.PRESET_FULL_RECT)
	g.z_index = LAMP_GLOW_Z   # 相对遮罩再抬一层，好盖在灯的图上
	host.add_child(g)


func _debug_tick(p: float, world: Color, lit: float) -> void:
	_debug_timer += 1
	if _debug_timer < 60:
		return
	_debug_timer = 0
	var sky_nodes := get_tree().get_nodes_in_group(SKY_GROUP)
	var n_sky := sky_nodes.size()
	if n_sky != _last_sky_count:
		_last_sky_count = n_sky
		print("[DayNight] \"%s\" 组当前 %d 个成员：" % [SKY_GROUP, n_sky])
		for s in sky_nodes:
			print("    %s" % s.get_path())

	# 报告组里【所有】光层，不管是自动建的还是你手摆的——
	# 只盯 _auto_light 的话，手摆节点接管后这里会一直显示"没建出来"，等于查错查错了地方。
	var members := get_tree().get_nodes_in_group(INDOOR_GROUP)
	var light_info := "组是空的"
	if not members.is_empty():
		var parts: Array[String] = []
		for m in members:
			var c := m as CanvasItem
			if c == null:
				parts.append("%s(不是CanvasItem)" % m.name)
				continue
			var rect_txt := str((c as Control).get_global_rect()) if c is Control else "非Control"
			parts.append("%s[%s] rect=%s vis=%s z=%d 加法=%s" % [
				c.name,
				("自动" if c == _auto_light else "手摆"),
				rect_txt, c.visible, c.z_index,
				str(c.material == _add_mat)])
		light_info = " | ".join(parts)


## 取一个铁定是白天的进度值（两条 Gradient 的白天段中点）
func _day_phase() -> float:
	return 0.5


## 光层挂在哪。优先 FullGameMode，找不到就退到主场景根节点——
## 两者都在世界那一层画布里（UI 在 CanvasLayer，不受影响），效果一样。
func _world_root() -> Node:
	var host := get_tree().current_scene
	if host == null:
		return null
	var n := host.find_child("FullGameMode", true, false)
	return n if n != null else host


## 只在原因变化时打一次，避免每帧刷屏
var _last_bail := ""
func _bail(why: String) -> void:
	if why == _last_bail:
		return
	_last_bail = why
	print("[DayNight] ✘ 光层没生成：%s" % why)


## 天空那几张图没加组的话，按场景结构自己找出来补进组。
## 这样窗外叠色和光层对齐都不再依赖"记得去编辑器点一下"。
## 你要是手动加了组，这里查到组非空就直接跳过，不插手。
func _ensure_sky_group() -> void:
	if not AUTO_FIND_SKY:
		return
	if not get_tree().get_nodes_in_group(SKY_GROUP).is_empty():
		return
	var world := _world_root()
	if world == null:
		return
	var cover := world.find_child(SKY_PARENT_NAME, true, false)
	if cover == null:
		return
	var n := 0
	for c in cover.get_children():
		if c is TextureRect:
			(c as TextureRect).add_to_group(SKY_GROUP)
			n += 1
	if n > 0:
		print("[DayNight] 自动把 %s 下的 %d 张天空图加进了 \"%s\" 组。" % [SKY_PARENT_NAME, n, SKY_GROUP])


## 读出两张叠层图【实际画了内容的那块区域】，只做一次。
##
## 为什么不能直接抄原图的裁剪坐标：你在 Procreate 里是新开画布画的（A4，3508×2480），
## 内容落在画布中间某处，而原图 glass_wall_3.png 的窗口在 (6, 1)。坐标系根本不是一套。
## 用 get_used_rect() 让引擎自己找非透明内容的外接框，这样你以后重导图挪了位置也不用改代码。
##
## 亮框的内容框 = 窗口本体（它和原图一样大，1:1 对齐）；
## 光晕的内容框比窗口大一圈（光要往外溢），两者的差值就是光晕该往外撑多少。
func _prepare_overlay_sources() -> void:
	if _overlay_ready:
		return
	_overlay_ready = true

	_night_tex = load(WINDOW_NIGHT_PATH) as Texture2D
	_frame_tex = load(WINDOW_FRAME_PATH) as Texture2D
	_glow_tex = load(WINDOW_GLOW_PATH) as Texture2D
	if _night_tex == null or _frame_tex == null or _glow_tex == null:
		_bail("叠层贴图读不到，检查这三个路径：%s / %s / %s"
			% [WINDOW_NIGHT_PATH, WINDOW_FRAME_PATH, WINDOW_GLOW_PATH])
		return

	var ni := _night_tex.get_image()
	var fi := _frame_tex.get_image()
	var gi := _glow_tex.get_image()
	if ni == null or fi == null or gi == null:
		_bail("叠层贴图取不到 Image（导入设置可能开了压缩）")
		return

	_night_src = Rect2(ni.get_used_rect())
	_frame_src = Rect2(fi.get_used_rect())
	_glow_src = Rect2(gi.get_used_rect())
	print("[DayNight] 叠层内容框：夜景=%s 亮框=%s 光晕=%s"
		% [_night_src, _frame_src, _glow_src])


## 给一张天空图挂上「光晕 + 亮框」两个子层。只建一次。
func _ensure_window_overlays(host: TextureRect) -> void:
	if host.has_node(WINDOW_FRAME_NODE):
		return
	_prepare_overlay_sources()
	if _frame_src.size.x <= 0.0 or _glow_src.size.x <= 0.0:
		return

	# 添加顺序 = 层序，后加的在上面：夜景 → 光晕 → 亮框。
	# 三层都原样贴，不加混合模式、不做颜色加工 —— 美术已经调好了，代码别再插一手。
	host.add_child(_make_overlay(WINDOW_NIGHT_NODE, _night_tex, _night_src))
	host.add_child(_make_overlay(WINDOW_GLOW_NODE, _glow_tex, _glow_src))
	host.add_child(_make_overlay(WINDOW_FRAME_NODE, _frame_tex, _frame_src))


func _make_overlay(node_name: String, tex: Texture2D, region: Rect2) -> TextureRect:
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = region

	var tr := TextureRect.new()
	tr.name = node_name
	tr.texture = at
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	return tr


func _update_window_overlays(host: TextureRect) -> void:
	# 夜景：和窗口 1:1，透明度跟夜色连续走，所以黄昏是真的在过渡，不是硬切。
	var night := host.get_node_or_null(WINDOW_NIGHT_NODE) as Control
	if night:
		night.visible = night_amount > 0.001
		night.modulate = Color(_comp.x, _comp.y, _comp.z, night_amount)

	# 亮框：和窗口 1:1，铺满父节点即可。室内受光，一直亮着，不参与昼夜。
	var frame := host.get_node_or_null(WINDOW_FRAME_NODE) as Control
	if frame:
		frame.visible = true
		frame.modulate = Color(_comp.x, _comp.y, _comp.z, 1.0)

	var glow := host.get_node_or_null(WINDOW_GLOW_NODE) as Control
	if glow == null:
		return

	# 光晕比窗口大一圈，所以要按源图里的差值往四周撑出去。
	# 父节点没开 clip_contents，撑出去的部分照样画得出来。
	var sx: float = host.size.x / maxf(_frame_src.size.x, 1.0)
	var sy: float = host.size.y / maxf(_frame_src.size.y, 1.0)
	glow.offset_left = (_glow_src.position.x - _frame_src.position.x) * sx
	glow.offset_top = (_glow_src.position.y - _frame_src.position.y) * sy
	glow.offset_right = (_glow_src.end.x - _frame_src.end.x) * sx
	glow.offset_bottom = (_glow_src.end.y - _frame_src.end.y) * sy

	glow.visible = _glow_a > 0.001
	glow.modulate = Color(_comp.x, _comp.y, _comp.z, _glow_a)


## sky_window 组的外接矩形 = 窗外那条玻璃带的实际位置。
func _sky_band() -> Rect2:
	var band := Rect2()
	var found := false
	for n in get_tree().get_nodes_in_group(SKY_GROUP):
		var c := n as Control
		if c == null:
			continue
		var r := c.get_global_rect()
		band = r if not found else band.merge(r)
		found = true
	return band if found else Rect2()


## 把光照遮罩往四周铺大，盖住整个可见画面。
## 必须记住原始矩形：不记的话每帧在上一帧的基础上再铺一次，节点会一路膨胀没边。
## 铺大之后灯会不会跑？不会 —— ref_min/ref_size 把灯的坐标锁回原始矩形，见下面。
func _pad_indoor_mask(c: Control) -> void:
	if c == null:
		return
	var key := c.get_instance_id()
	if not _indoor_orig.has(key):
		_indoor_orig[key] = Rect2(c.position, c.size)
	var o: Rect2 = _indoor_orig[key]

	var pad_tl := Vector2(MASK_PAD_X, MASK_PAD_TOP)
	var full_size := o.size + pad_tl + Vector2(MASK_PAD_X, MASK_PAD_BOTTOM)
	c.position = o.position - pad_tl
	c.size = full_size

	# 原始矩形在铺大后的遮罩里占哪一块 —— 灯的所有坐标都相对它算
	_ref_min = pad_tl / full_size
	_ref_size = o.size / full_size
	_ref_aspect = o.size.x / maxf(o.size.y, 1.0)
	_ref_global = Rect2(c.global_position + pad_tl, o.size)


## 没人往 indoor_light 组里放东西的话，自己建一个。
## 好处是不用改 main.tscn；你哪天想手摆，放个节点进组就会接管。
func _ensure_indoor_light() -> void:
	if not INDOOR_AUTO_CREATE:
		_bail("INDOOR_AUTO_CREATE = false")
		return
	if is_instance_valid(_auto_light):
		return
	if not get_tree().get_nodes_in_group(INDOOR_GROUP).is_empty():
		_bail("\"%s\" 组里已经有节点了，自动生成让位" % INDOOR_GROUP)
		return

	var world := _world_root()
	if world == null:
		_bail("找不到挂载点：current_scene=%s" % str(get_tree().current_scene))
		return

	var tr := TextureRect.new()
	tr.name = "IndoorLightAuto"
	tr.texture = INDOOR_LIGHT_TEX
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.z_index = INDOOR_LIGHT_Z
	tr.add_to_group(INDOOR_GROUP)
	world.add_child(tr)
	world.move_child(tr, world.get_child_count() - 1)   # 排最后 + 高 z_index，双保险盖在最上面
	_auto_light = tr
	print("[DayNight] ✔ 光层已生成，挂在 %s 下（该节点共 %d 个子节点）"
		% [world.name, world.get_child_count()])


## 把自动光层贴着天空带的下沿对齐：横向跟天空一样宽，纵向从天空底边往下。
## 这样"办公室区域（不含上面那一小条）"是算出来的，不是我猜的坐标。
func _layout_indoor_light() -> void:
	if not is_instance_valid(_auto_light):
		return

	var band := Rect2()
	var found := false
	for n in get_tree().get_nodes_in_group(SKY_GROUP):
		var c := n as Control
		if c == null:
			continue
		var r := c.get_global_rect()
		band = r if not found else band.merge(r)
		found = true

	if found:
		_auto_light.global_position = Vector2(
			band.position.x, band.end.y + INDOOR_LIGHT_TOP_BIAS)
		_auto_light.size = Vector2(band.size.x, INDOOR_LIGHT_HEIGHT)
		return

	# 天空没加组 → 整套窗外效果都是哑的。喊一声，别默默失效。
	if not _warned_no_sky:
		_warned_no_sky = true
		print("[DayNight] ⚠ 窗外那几张天空 TextureRect 还没加进 \"%s\" 组：" % SKY_GROUP
			+ "天空叠色不会生效，室内光层只能用 Floors 的范围兜底（比实际窄）。")

	# 兜底：拿 Floors 的范围，上沿往下让开天空带的高度
	var wr := _world_root()
	var floors := (wr.find_child("Floors", true, false) if wr else null) as Control
	if floors == null:
		return
	var fr := floors.get_global_rect()
	_auto_light.global_position = Vector2(
		fr.position.x, fr.position.y + FALLBACK_SKY_BAND_H + INDOOR_LIGHT_TOP_BIAS)
	_auto_light.size = Vector2(fr.size.x, INDOOR_LIGHT_HEIGHT)


func _get_canvas_modulate() -> CanvasModulate:
	if is_instance_valid(_canvas_mod):
		return _canvas_mod

	var host := get_tree().current_scene
	if host == null:
		return null

	# 场景里已经有就复用（一个 canvas 只能有一个 CanvasModulate，多了引擎会报警告）
	for c in host.get_children():
		if c is CanvasModulate:
			_canvas_mod = c
			return _canvas_mod

	# 没有就自己建一个，挂在主场景根节点下 = 默认 canvas，
	# 只影响世界；UI 在 CanvasLayer 里，不受影响。
	var cm := CanvasModulate.new()
	cm.name = "DayNightModulate"
	host.add_child(cm)
	_canvas_mod = cm
	return _canvas_mod
