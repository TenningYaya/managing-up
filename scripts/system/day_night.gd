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

## ── 室内开灯 ────────────────────────────────────────────────
## 加法混合：最终颜色 = 底下的画面 + 这个颜色 × 强度。所以它只会提亮，
## 不会像 modulate 那样把东西弄脏。偏暖 = 白炽灯，越白越像日光灯。
const INDOOR_LIGHT_COLOR := Color(1.0, 0.82, 0.55)
const INDOOR_LIGHT_STRENGTH := 0.28   ## 夜晚最亮时叠多少。太大会糊成一片，从小往上调
const INDOOR_LIGHT_DAY := 0.0         ## 白天叠多少（0 = 白天不开灯）
## 光心：纵向 0 = 贴着窗户，1 = 贴着地板。0.45 = 桌子和人那一带最亮，窗边和地板都暗。
## 夜里别用 0 —— 那等于"窗外往屋里打光"，可窗外是黑的，说不通。
const INDOOR_LIGHT_CENTER := 0.45
const INDOOR_LIGHT_REACH := 0.75      ## 光摊多开。越大越均匀，越小越像一道光带
const INDOOR_LIGHT_FALLOFF := 1.8     ## 衰减陡峭度。1 = 线性；越大光斑边界越明显
const INDOOR_LIGHT_EDGE := 0.12       ## 左右边缘收多少，免得光层两侧是硬切口
const INDOOR_SHADER: Shader = preload("res://data/shader/indoor_light.gdshader")

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
var night_amount: float = 0.0 ## 0 = 大白天，1 = 全黑。给别的系统当钩子用

var debug_phase: float = -1.0 ## ≥0 时锁定进度，方便调色；-1 = 跟随时间

var _add_mat: ShaderMaterial
var _canvas_mod: CanvasModulate = null
var _auto_light: TextureRect = null   ## 自动生成的那个光层，只有它才走自动对齐
var _warned_no_sky := false
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

	phase = fposmod(Gamemanager.total_time / CYCLE_SECONDS + PHASE_OFFSET, 1.0)
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

	# ── 屋里：开灯。加法混合，强度跟着夜的浓度走 ──
	_ensure_indoor_light()
	_layout_indoor_light()
	# 衰减和加法混合都在 shader 里，所以挂 ColorRect 也有层次，不挑节点类型。
	# compensate 把"天黑"对光层的压暗除掉，不然越黑越看不见灯，等于白开。
	var lit: float = lerpf(INDOOR_LIGHT_DAY, INDOOR_LIGHT_STRENGTH, night_amount)
	_add_mat.set_shader_parameter("light_color", INDOOR_LIGHT_COLOR)
	_add_mat.set_shader_parameter("strength", lit)
	_add_mat.set_shader_parameter("light_center", INDOOR_LIGHT_CENTER)
	_add_mat.set_shader_parameter("light_reach", INDOOR_LIGHT_REACH)
	_add_mat.set_shader_parameter("falloff", INDOOR_LIGHT_FALLOFF)
	_add_mat.set_shader_parameter("edge_softness", INDOOR_LIGHT_EDGE)
	_add_mat.set_shader_parameter("compensate", Vector3(
		1.0 / maxf(world.r, 0.001),
		1.0 / maxf(world.g, 0.001),
		1.0 / maxf(world.b, 0.001)))

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

	# ── 窗户亮灯：透明度直接跟"夜的强度"走 ──
	for n in get_tree().get_nodes_in_group(LIGHTS_GROUP):
		var ci := n as CanvasItem
		if ci:
			ci.modulate = Color(LIGHTS_BOOST, LIGHTS_BOOST, LIGHTS_BOOST, night_amount)

	if DEBUG_LOG:
		_debug_tick(p, world, lit)


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

	print("[DayNight] phase=%.2f 夜浓度=%.2f 窗灯=%.2f 室内压暗=%s 开灯量=%.3f 天空节点=%d 光层×%d：%s"
		% [p, night_amount, _glow_a, world, lit, n_sky, members.size(), light_info])


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
