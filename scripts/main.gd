# main.gd
extends Control

# ➕ 鼠标穿透相关
# 原理：在 Windows 上，只有 DisplayServer.window_set_mouse_passthrough(region) 能把点击
#      "穿透"到其它程序；WINDOW_FLAG_MOUSE_PASSTHROUGH 只会穿透到"本程序自己的窗口"，没用。
#      region 内 = 可点击且会绘制；region 外 = 既穿透点击、又显示桌面（窗口被裁剪掉那块）。
#      因此 region 必须覆盖"所有需要被看见/被点到"的区域 = 底部条 + 当前可见的浮窗。
const BOTTOM_STRIP_HEIGHT := 435.0          # 底部固定窗口高度（画布坐标，随分辨率缩放）
const DEBUG_PASSTHROUGH := false            # 需要排查时改 true，会打印每次 region 更新
const SETTINGS_PATH := "user://settings.cfg" # 轻量设置持久化（与游戏存档分离，删档也不影响）
var interactive_panels: Array[Control] = [] # 底部条之外、显示时也要进 region 的浮窗
var _passthrough_active := false            # 全屏模式 true / 便签模式同样 true（只是 panels 不同）
var _passthrough_suppress_count := 0        # >0 = 有界面（教程/弹窗…）要求整屏可见；引用计数，支持叠加

# --- 便签模式 ---
var _is_sticky_mode := false
var _sticky_note: Control = null      # 运行时实例，与主场景完全独立
var _sticky_canvas: CanvasLayer = null

var window_height_fraction := 0.99  # 当前窗口高度占可用屏幕高的比例；设置页可改、便签往返/重启后保持

# --- 2. Initialization ---
func _ready():

	# 接管"关闭窗口"事件:不再让系统直接退出,改为先存档再退出(见 _notification)
	get_tree().auto_accept_quit = false

	SaveManager.load_game()

	# —— 全屏透明覆盖窗口 ——
	# ⚠️ 用"无边框窗口铺满屏幕"实现全屏，绝不能用 WINDOW_MODE_FULLSCREEN：
	#    独占全屏会让透明背景和点击穿透同时失效。
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_min_size(Vector2i(0, 0))        # ← 加这行
	DisplayServer.window_set_size(Vector2i(1920, 600))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, _load_always_on_top())   # 读取设置，默认置顶
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)     # 确保窗口可透明
	get_viewport().transparent_bg = true

	# 运行时窗口/任务栏图标（用项目里的 logo）
	var _icon_tex: Texture2D = load("res://assets/figures/table_icon.png")
	if _icon_tex:
		DisplayServer.set_icon(_icon_tex.get_image())

	await get_tree().process_frame  # 等模式切换生效再查询可用区域
	print("after second await: size=", DisplayServer.window_get_size())
	window_height_fraction = _load_window_height_fraction()  # 读取上次保存的窗口大小比例
	await _cover_current_screen()

	$FullGameMode.show()

	# 底部条之外、显示时也要保持可点击+可见的浮窗。
	# 其余 UI 都在底部 435 条内，由底部条统一覆盖。
	# 注：RecruitmentPanel / EmployeeWarehouse 的拖动已在别处实现，这里只读它们的实时位置。
	interactive_panels = [
		$CanvasLayer/RecruitmentPanel,   # 可移动
		$CanvasLayer/EmployeeWarehouse,  # 可移动
		$CanvasLayer/EmployeePanel,      # 不可移动（平时隐藏，选中员工时才出现）
		$CanvasLayer/OfficePanel,
	]
	# ⚠️ TutorialLayer 是 CanvasLayer（不是 Control，没有 get_global_rect），不能放进上面的数组。
	#    而且教程运行时几乎铺满全屏（黑幕挖洞 + 对话/提示到处出现），用包围盒也圈不住。
	#    所以教程改用"整屏不穿透"策略（见 suppress_passthrough），由 tutorial_layer.gd 结束时释放。

	# 👉 全屏模式：启用 region 穿透
	_passthrough_active = true

	# ⚠️ window_set_mouse_passthrough 设的是“窗口”级全局状态。场景重载（删档重开教程 / 改语言）
	#    不会重建窗口，上一个 Main 实例残留在 DisplayServer 里的旧 region 会原样保留；而新 Main 的
	#    _last_pts 又被初始化回空，导致 _process 在抑制态（教程中 suppress_count>0）下判定
	#    “没设过 region 无需清”，于是旧 region 继续裁屏——教程里居中偏上的 KPI宝(画布 y≈538) 正好
	#    落在旧 region 之外被裁掉、看不见。所以这里强制清一次，让新 Main 从“整窗可见”的干净状态开始。
	_clear_region()

	# 教程进行中：先整屏可见可点（教程 UI 铺满全屏，不能被 region 裁掉），
	# 教程结束（tutorial_layer 被销毁）时会调用 suppress_passthrough(false) 自动恢复。
	if has_node("TutorialLayer") and not Gamemanager.is_tutorial_completed:
		_passthrough_suppress_count += 1

	print("window mode: ", DisplayServer.window_get_mode())

	# 注：工位的解锁显隐由各 DeskSlot 自己监听 level_changed 并按 unlock_at_level 处理
	# （见 DeskSlot.gd），main 不再按容器位置统一控制——否则会误伤 DeskRow 里的
	# EmployeeDropArea 等非工位节点，并打乱被它隔开的工位解锁等级。

	# --- 创建独立的 StickyNote（独立 CanvasLayer，不受 Camera2D 影响）---
	_sticky_canvas = CanvasLayer.new()
	_sticky_canvas.layer = 100
	add_child(_sticky_canvas)

	_sticky_note = load("res://scenes/UI/sticky_note.tscn").instantiate()
	_sticky_canvas.add_child(_sticky_note)

	# 初始位置：屏幕右下角
	await get_tree().process_frame
	var vp := get_viewport().get_visible_rect().size
	_sticky_note.position = vp - _sticky_note.size
	_sticky_note.hide()


# 让窗口铺满它当前所在的那块屏幕（支持任意分辨率 / 多显示器），排除任务栏
#func _cover_current_screen() -> void:
	#var scr := DisplayServer.window_get_current_screen()
	#var usable := DisplayServer.screen_get_usable_rect(scr)
	##DisplayServer.window_set_position(usable.position)
	##DisplayServer.window_set_size(Vector2i(usable.size.x, usable.size.y - 1))
	#var default_y_offset := 50  # 这个值自己调，单位是物理像素
	#DisplayServer.window_set_position(Vector2i(usable.position.x, usable.position.y - default_y_offset))
	#DisplayServer.window_set_size(Vector2i(usable.size.x, usable.size.y - 1))
	
func _cover_current_screen():
	var scr := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(scr)
	var win_h := int(usable.size.y * window_height_fraction)
	DisplayServer.window_set_min_size(Vector2i(0, 0))
	DisplayServer.window_set_size(Vector2i(usable.size.x, win_h))
	DisplayServer.window_set_position(Vector2i(usable.position.x, usable.end.y - win_h))
	
# 读取“是否置顶”设置（默认 false = 不置顶，可被其它窗口遮挡；勾选后才置顶）
func _load_always_on_top() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		return bool(cfg.get_value("window", "always_on_top", false))
	return false


# 由设置界面的勾选框调用：勾选=置顶；取消=可被其它窗口遮挡。并持久化保存
func set_always_on_top(enabled: bool) -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, enabled)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # 不存在则为空配置，忽略返回值
	cfg.set_value("window", "always_on_top", enabled)
	cfg.save(SETTINGS_PATH)


# 读取上次保存的窗口高度比例（默认沿用当前值 0.99）
func _load_window_height_fraction() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		return float(cfg.get_value("window", "height_fraction", window_height_fraction))
	return window_height_fraction


# 由设置界面的窗口大小下拉框调用：更新比例 + 立即重新覆盖屏幕 + 持久化。
# 这样切便签模式往返、以及重启游戏后，玩家选的窗口大小都能保持。
func set_window_height_fraction(frac: float) -> void:
	window_height_fraction = clampf(frac, 0.1, 1.0)
	_cover_current_screen()
	_last_pts = PackedVector2Array()  # 强制下一帧用新尺寸重算穿透 region
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("window", "height_fraction", window_height_fraction)
	cfg.save(SETTINGS_PATH)


# 关窗口 / 切到别的程序时自动存档,尽量不丢进度
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			# 玩家点了关闭按钮:先存档再真正退出(auto_accept_quit 已设为 false)
			if Gamemanager.is_tutorial_completed and SaveManager.has_method("save_game"):
				SaveManager.save_game()
			get_tree().quit()
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			# 玩家切到别的程序:顺手存一次(autosave 内部有节流,不会狂存)
			if SaveManager.has_method("autosave"):
				SaveManager.autosave()

# --- 3. 穿透 region 维护 ---
# ⚠️ 关键：window_set_mouse_passthrough 的 region 不仅决定“哪里能点”，还会【裁剪窗口显示】
#    （region 外直接显示桌面）。所以 region 必须覆盖所有要被看见的 UI。
# 旧实现把“底部条 + 所有浮窗”合成一个【包围盒】：底部条是满屏宽，合并后从最高浮窗顶一直到底
#    整条横带都被圈进 region → 浮窗左右的空白也点不透（就是你遇到的横带问题）。
# 新实现改成【天际线(skyline)多边形】：底部满宽条 + 仅每个浮窗“自己那一竖列”向上探出。
#    浮窗依旧被完整覆盖（不会被裁掉），但浮窗左右的空白重新可以穿透点击到桌面。
var _last_pts := PackedVector2Array()   # 上次设置的穿透多边形，变化时才重设（省开销、避免闪烁）

func _process(_dt):
	if not _passthrough_active:
		return
	# 教程/弹窗等场景：临时整屏可见可点，不做裁剪（只在刚进入抑制时清一次）
	if _passthrough_suppress_count > 0:
		if not _last_pts.is_empty():
			_clear_region()
		return
	var pts := _compute_region_polygon()
	if pts != _last_pts:
		_last_pts = pts
		DisplayServer.window_set_mouse_passthrough(pts)
		if DEBUG_PASSTHROUGH:
			print("[PT] region pts = ", pts.size())


# 底部条（画布坐标 → 物理窗口像素）。get_screen_transform 已包含缩放与黑边偏移，兼容任意分辨率
# 便签模式下返回空 Rect，region 只由 _sticky_note 决定
func _band_physical_rect() -> Rect2:
	if _is_sticky_mode:
		return Rect2()
	var vp := get_viewport().get_visible_rect().size
	var band_canvas := Rect2(0.0, vp.y - BOTTOM_STRIP_HEIGHT, vp.x, BOTTOM_STRIP_HEIGHT)
	return get_viewport().get_screen_transform() * band_canvas


# 计算穿透多边形：底部满宽条 + 各可见浮窗的“天际线”。只把浮窗自己那一竖列向上算进来，
# 而不是取整体包围盒把一整条横带圈死。坐标向外取整，避免亚像素抖动导致每帧重设。
func _compute_region_polygon() -> PackedVector2Array:
	var band := _band_physical_rect()

	# 便签模式（无底部条）：区域就用可见浮窗自身矩形（只有一个小便签，不存在横带问题）
	if band == Rect2():
		var r := Rect2()
		var has := false
		for panel in interactive_panels:
			if is_instance_valid(panel) and panel.is_visible_in_tree():
				var pr := get_viewport().get_screen_transform() * panel.get_global_rect()
				r = pr if not has else r.merge(pr)
				has = true
		if not has:
			return PackedVector2Array()
		r = Rect2(r.position.floor(), r.size.ceil())
		return PackedVector2Array([
			r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)
		])

	var left := floorf(band.position.x)
	var right := ceilf(band.end.x)
	var band_top := floorf(band.position.y)
	var bottom := ceilf(band.end.y)

	# 收集“探出底部条上方”的浮窗：记录 x 区间与顶部 y（x 夹在底部条宽度内，向外取整）
	var bumps := []
	for panel in interactive_panels:
		if is_instance_valid(panel) and panel.is_visible_in_tree():
			var pr := get_viewport().get_screen_transform() * panel.get_global_rect()
			var px1 := clampf(floorf(pr.position.x), left, right)
			var px2 := clampf(ceilf(pr.end.x), left, right)
			if px2 - px1 <= 0.5:
				continue
			var ptop := floorf(pr.position.y)
			if ptop < band_top:   # 只有高出底部条的部分才需要额外覆盖
				bumps.append({"x1": px1, "x2": px2, "top": ptop})

	# 没有浮窗探出 → 区域就是底部满宽条
	if bumps.is_empty():
		return PackedVector2Array([
			Vector2(left, band_top), Vector2(right, band_top),
			Vector2(right, bottom), Vector2(left, bottom)
		])

	# 用浮窗的 x 边界把 [left,right] 切成若干格，每格取其上方最高的浮窗顶（min y）
	var xs := [left, right]
	for b in bumps:
		xs.append(b.x1)
		xs.append(b.x2)
	xs.sort()
	var ux := []
	for x in xs:
		if ux.is_empty() or absf(x - ux[ux.size() - 1]) > 0.5:
			ux.append(x)

	var cells := []
	for i in range(ux.size() - 1):
		var xa: float = ux[i]
		var xb: float = ux[i + 1]
		var top := band_top
		for b in bumps:
			if b.x1 <= xa + 0.5 and b.x2 >= xb - 0.5:
				top = minf(top, b.top)
		# 与上一格同高就合并，减少多边形顶点
		if not cells.is_empty() and absf(cells[cells.size() - 1].top - top) <= 0.5:
			cells[cells.size() - 1].x2 = xb
		else:
			cells.append({"x1": xa, "x2": xb, "top": top})

	# 描出直角多边形：左下 → 左上 → 沿天际线阶梯走到右上 → 右下（底边自动闭合回左下）
	var pts := PackedVector2Array()
	pts.append(Vector2(left, bottom))
	pts.append(Vector2(left, cells[0].top))
	for i in range(cells.size()):
		var c = cells[i]
		pts.append(Vector2(c.x2, c.top))
		if i < cells.size() - 1:
			pts.append(Vector2(c.x2, cells[i + 1].top))
	pts.append(Vector2(right, bottom))
	return pts


# 清除 region（整窗都可点击、不裁剪）
func _clear_region() -> void:
	_last_pts = PackedVector2Array()
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array())


# 给外部（教程 / 弹窗 / 全屏菜单等：铺满屏幕、或出现在底部条之外的 UI）调用：
#   true  = 请求"临时整屏可见可点"（关闭裁剪/穿透）
#   false = 释放该请求
# 用引用计数，允许多个界面同时要求整屏（如教程中弹出对话框）；全部释放后下一帧自动重建 region。
func suppress_passthrough(active: bool) -> void:
	if active:
		_passthrough_suppress_count += 1
	else:
		_passthrough_suppress_count = max(0, _passthrough_suppress_count - 1)


# --- 4. 输入监听 ---
func _input(event):
	if event.is_action_pressed("toggle_sticky_mode"):
		_toggle_mode()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_UP or event.keycode == KEY_DOWN:
			_move_window_y(event.keycode == KEY_UP)
			get_viewport().set_input_as_handled()

func _move_window_y(up: bool) -> void:
	var scr := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(scr)
	var dpi := DisplayServer.screen_get_dpi(scr)
	var step_px := int(5.0 / 2.54 * dpi)
	var pos := DisplayServer.window_get_position()
	var win_h := DisplayServer.window_get_size().y
	print("before: pos=", pos, " win_h=", win_h, " step=", step_px, " max_y=", usable.end.y - win_h)
	pos.y += -step_px if up else step_px
	pos.y = clampi(pos.y, usable.position.y, usable.end.y - win_h)
	DisplayServer.window_set_position(pos)
	print("after set: pos_now=", DisplayServer.window_get_position())
	_last_pts = PackedVector2Array()
	
# --- 5. 模式切换逻辑 ---
func _toggle_mode():
	_is_sticky_mode = !_is_sticky_mode
	if _is_sticky_mode:
		_enter_sticky_mode()
	else:
		_exit_sticky_mode()


func _enter_sticky_mode():
	$FullGameMode.hide()
	$CanvasLayer.hide()
	_sticky_note.show()
	# 穿透 region 只暴露 StickyNote，其余全透
	interactive_panels = [_sticky_note]
	_last_pts = PackedVector2Array()  # 强制下一帧重算


func _exit_sticky_mode():
	_sticky_note.hide()
	$FullGameMode.show()
	$CanvasLayer.show()
	# 恢复游戏面板列表
	interactive_panels = [
		$CanvasLayer/RecruitmentPanel,
		$CanvasLayer/EmployeeWarehouse,
		$CanvasLayer/EmployeePanel,
		$CanvasLayer/OfficePanel,
	]
	_cover_current_screen()
	_last_pts = PackedVector2Array()  # 强制下一帧重算
