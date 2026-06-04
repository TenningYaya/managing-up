extends Control

# --- 1. 变量定义 ---
var is_sticky = false

# 拖拽相关变量（便签模式下拖动整个 OS 窗口）
var is_dragging = false
var mouse_offset = Vector2i()

# ➕ 鼠标穿透相关
# 原理：在 Windows 上，只有 DisplayServer.window_set_mouse_passthrough(region) 能把点击
#      “穿透”到其它程序；WINDOW_FLAG_MOUSE_PASSTHROUGH 只会穿透到“本程序自己的窗口”，没用。
#      region 内 = 可点击且会绘制；region 外 = 既穿透点击、又显示桌面（窗口被裁剪掉那块）。
#      因此 region 必须覆盖“所有需要被看见/被点到”的区域 = 底部条 + 当前可见的浮窗。
const BOTTOM_STRIP_HEIGHT := 435.0          # 底部固定窗口高度（画布坐标，随分辨率缩放）
const DEBUG_PASSTHROUGH := false            # 需要排查时改 true，会打印每次 region 更新
var interactive_panels: Array[Control] = [] # 底部条之外、显示时也要进 region 的浮窗
var _passthrough_active := false            # 全屏模式 true / 便签模式 false
var _last_region := Rect2(-1, -1, -1, -1)   # 上次设置的 region，变化时才重设（省开销、避免闪烁）
var _passthrough_suppressed := false        # 教程等需要“整屏可见可点”时为 true（临时关闭裁剪/穿透）

# ➕ 获取包含 5排工位 的父节点
@onready var desk_row = $FullGameMode/Background/WholeAlignment/DeskRow

# --- 2. Initialization ---
func _ready():

	SaveManager.load_game()

	# —— 全屏透明覆盖窗口 ——
	# ⚠️ 用“无边框窗口铺满屏幕”实现全屏，绝不能用 WINDOW_MODE_FULLSCREEN：
	#    独占全屏会让透明背景和点击穿透同时失效。
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)   # 常驻其他程序之上
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)     # 确保窗口可透明
	get_viewport().transparent_bg = true

	_cover_current_screen()

	$FullGameMode.show()
	$StickyNote.hide()

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
	#    所以教程改用“整屏不穿透”策略（见 suppress_passthrough），由 tutorial_layer.gd 结束时释放。

	# 👉 全屏模式：启用 region 穿透
	_passthrough_active = true

	# 教程进行中：先整屏可见可点（教程 UI 铺满全屏，不能被 region 裁掉），
	# 教程结束（tutorial_layer 被销毁）时会调用 suppress_passthrough(false) 自动恢复。
	if has_node("TutorialLayer") and not Gamemanager.is_tutorial_completed:
		_passthrough_suppressed = true

	print("window mode: ", DisplayServer.window_get_mode())

	# ➕ 监听 Gamemanager 的玩家升级信号
	Gamemanager.level_changed.connect(_on_player_level_changed)

	# ➕ 游戏刚启动时，初始化一次桌子的显示状态
	_update_desk_visibility()


# 让窗口铺满它当前所在的那块屏幕（支持任意分辨率 / 多显示器）
func _cover_current_screen() -> void:
	var scr := DisplayServer.window_get_current_screen()
	DisplayServer.window_set_position(DisplayServer.screen_get_position(scr))
	DisplayServer.window_set_size(DisplayServer.screen_get_size(scr))


# --- 3. 穿透 region 维护 ---
# 每帧计算“底部条 + 可见浮窗”的包围盒，只有它变化时才重设 region。
# 这样开关/拖动面板、改分辨率都会自动跟随，且不会每帧调用原生 API。
func _process(_dt):
	if not _passthrough_active:
		return
	# 教程等场景：临时整屏可见可点，不做 region 裁剪（只在刚进入抑制时清一次）
	if _passthrough_suppressed:
		if _last_region != Rect2(-1, -1, -1, -1):
			_clear_region()
		return
	var region := _compute_region()
	if region != _last_region:
		_last_region = region
		_apply_region(region)


# 底部条（画布坐标 → 物理窗口像素）。get_screen_transform 已包含缩放与黑边偏移，兼容任意分辨率
func _band_physical_rect() -> Rect2:
	var vp := get_viewport().get_visible_rect().size
	var band_canvas := Rect2(0.0, vp.y - BOTTOM_STRIP_HEIGHT, vp.x, BOTTOM_STRIP_HEIGHT)
	return get_viewport().get_screen_transform() * band_canvas


# region = 底部条 + 当前可见浮窗 的整体包围盒（物理像素，取整避免亚像素抖动反复重设）
func _compute_region() -> Rect2:
	var bb := _band_physical_rect()
	for panel in interactive_panels:
		if is_instance_valid(panel) and panel.is_visible_in_tree():
			bb = bb.merge(get_viewport().get_screen_transform() * panel.get_global_rect())
	return Rect2(bb.position.floor(), bb.size.ceil())


func _apply_region(r: Rect2) -> void:
	var pts := PackedVector2Array([
		r.position,
		Vector2(r.position.x + r.size.x, r.position.y),
		r.position + r.size,
		Vector2(r.position.x, r.position.y + r.size.y),
	])
	DisplayServer.window_set_mouse_passthrough(pts)
	if DEBUG_PASSTHROUGH:
		print("[PT] region set to ", r)


# 清除 region（整窗都可点击、不裁剪）——便签模式用
func _clear_region() -> void:
	_last_region = Rect2(-1, -1, -1, -1)
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array())


# 给外部（如 tutorial_layer）调用：
#   true  = 临时整屏可见可点（关闭裁剪/穿透），适合教程、全屏菜单等铺满全屏的 UI
#   false = 恢复正常 region 穿透（下一帧 _process 自动重建 region）
func suppress_passthrough(active: bool) -> void:
	_passthrough_suppressed = active


# --- 4. 输入监听 ---
func _input(event):
	if event.is_action_pressed("toggle_sticky_mode"):
		toggle_mode()

	if is_sticky:
		handle_drag(event)


# --- 5. 模式切换逻辑 ---
func toggle_mode():
	is_sticky = !is_sticky

	if is_sticky:
		enter_sticky_mode()
	else:
		exit_sticky_mode()


func enter_sticky_mode():
	# UI切换
	$FullGameMode.hide()
	$StickyNote.show()
	$CanvasLayer.hide()

	# 👉 停止 region 维护，并清除裁剪：便签是个独立小窗口，整窗都要可点击
	_passthrough_active = false
	_clear_region()

	# 缩小窗口（置顶在 _ready 已开启，无需重复设置）
	DisplayServer.window_set_size(Vector2i(270, 360))


func exit_sticky_mode():
	# UI恢复
	$StickyNote.hide()
	$FullGameMode.show()
	$CanvasLayer.show()

	# 恢复全屏覆盖
	_cover_current_screen()

	# 👉 重新启用 region 穿透（下一帧 _process 会重建 region）
	_passthrough_active = true


# --- 6. 便签拖拽逻辑（拖动整个 OS 窗口）---
func handle_drag(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_dragging = true
				var mouse_pos = DisplayServer.mouse_get_position()
				var window_pos = DisplayServer.window_get_position()
				mouse_offset = mouse_pos - window_pos
			else:
				is_dragging = false

	if event is InputEventMouseMotion and is_dragging:
		var current_mouse_pos = DisplayServer.mouse_get_position()
		DisplayServer.window_set_position(current_mouse_pos - mouse_offset)


# ================================
# ✅ 工位显示与隐藏控制逻辑
# ================================

func _on_player_level_changed(_new_level: int):
	# 只要玩家升级（level_changed 发出信号），就重新检查并刷新桌子显示
	_update_desk_visibility()

func _update_desk_visibility():
	if not desk_row: return
	var slots = desk_row.get_children()

	for i in range(slots.size()):
		var slot = slots[i]
		if i < Gamemanager.player_level:
			# 解锁状态：完全可见，并启用升级按钮
			slot.modulate.a = 1.0
			if slot.has_node("UpgradeTriggerBtn"):
				slot.get_node("UpgradeTriggerBtn").disabled = false
		else:
			# 未解锁状态：变成全透明（但保留布局占位），并禁用升级按钮防止误触
			slot.modulate.a = 0.0
			if slot.has_node("UpgradeTriggerBtn"):
				slot.get_node("UpgradeTriggerBtn").disabled = true
