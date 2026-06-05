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
var _last_region := Rect2(-1, -1, -1, -1)   # 上次设置的 region，变化时才重设（省开销、避免闪烁）
var _passthrough_suppress_count := 0        # >0 = 有界面（教程/弹窗…）要求整屏可见；引用计数，支持叠加

# --- 便签模式 ---
var _is_sticky_mode := false
var _sticky_note: Control = null      # 运行时实例，与主场景完全独立
var _sticky_canvas: CanvasLayer = null

# ➕ 获取包含 5排工位 的父节点
@onready var desk_row = $FullGameMode/Background/WholeAlignment/DeskRow

# --- 2. Initialization ---
func _ready():

	SaveManager.load_game()

	# —— 全屏透明覆盖窗口 ——
	# ⚠️ 用"无边框窗口铺满屏幕"实现全屏，绝不能用 WINDOW_MODE_FULLSCREEN：
	#    独占全屏会让透明背景和点击穿透同时失效。
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, _load_always_on_top())   # 读取设置，默认置顶
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)     # 确保窗口可透明
	get_viewport().transparent_bg = true

	_cover_current_screen()

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

	# 教程进行中：先整屏可见可点（教程 UI 铺满全屏，不能被 region 裁掉），
	# 教程结束（tutorial_layer 被销毁）时会调用 suppress_passthrough(false) 自动恢复。
	if has_node("TutorialLayer") and not Gamemanager.is_tutorial_completed:
		_passthrough_suppress_count += 1

	print("window mode: ", DisplayServer.window_get_mode())

	# ➕ 监听 Gamemanager 的玩家升级信号
	Gamemanager.level_changed.connect(_on_player_level_changed)

	# ➕ 游戏刚启动时，初始化一次桌子的显示状态
	_update_desk_visibility()

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


# 让窗口铺满它当前所在的那块屏幕（支持任意分辨率 / 多显示器）
func _cover_current_screen() -> void:
	var scr := DisplayServer.window_get_current_screen()
	DisplayServer.window_set_position(DisplayServer.screen_get_position(scr))
	DisplayServer.window_set_size(DisplayServer.screen_get_size(scr))


# 读取"是否置顶"设置（默认 true = 置顶）
func _load_always_on_top() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		return bool(cfg.get_value("window", "always_on_top", true))
	return true


# 由设置界面的勾选框调用：勾选=置顶；取消=可被其它窗口遮挡。并持久化保存
func set_always_on_top(enabled: bool) -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, enabled)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # 不存在则为空配置，忽略返回值
	cfg.set_value("window", "always_on_top", enabled)
	cfg.save(SETTINGS_PATH)


# --- 3. 穿透 region 维护 ---
# 每帧计算"底部条 + 可见浮窗"的包围盒，只有它变化时才重设 region。
# 这样开关/拖动面板、改分辨率都会自动跟随，且不会每帧调用原生 API。
func _process(_dt):
	if not _passthrough_active:
		return
	# 教程/弹窗等场景：临时整屏可见可点，不做 region 裁剪（只在刚进入抑制时清一次）
	if _passthrough_suppress_count > 0:
		if _last_region != Rect2(-1, -1, -1, -1):
			_clear_region()
		return
	var region := _compute_region()
	if region != _last_region:
		_last_region = region
		_apply_region(region)


# 底部条（画布坐标 → 物理窗口像素）。get_screen_transform 已包含缩放与黑边偏移，兼容任意分辨率
# 便签模式下返回空 Rect，region 只由 _sticky_note 决定
func _band_physical_rect() -> Rect2:
	if _is_sticky_mode:
		return Rect2()
	var vp := get_viewport().get_visible_rect().size
	var band_canvas := Rect2(0.0, vp.y - BOTTOM_STRIP_HEIGHT, vp.x, BOTTOM_STRIP_HEIGHT)
	return get_viewport().get_screen_transform() * band_canvas


# region = 底部条 + 当前可见浮窗 的整体包围盒（物理像素，取整避免亚像素抖动反复重设）
func _compute_region() -> Rect2:
	var bb := _band_physical_rect()
	var has_bb := bb != Rect2()
	for panel in interactive_panels:
		if is_instance_valid(panel) and panel.is_visible_in_tree():
			var r := get_viewport().get_screen_transform() * panel.get_global_rect()
			bb = r if not has_bb else bb.merge(r)
			has_bb = true
	if not has_bb:
		return Rect2()
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


# 清除 region（整窗都可点击、不裁剪）
func _clear_region() -> void:
	_last_region = Rect2(-1, -1, -1, -1)
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
	_last_region = Rect2(-1, -1, -1, -1)  # 强制下一帧重算


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
	_last_region = Rect2(-1, -1, -1, -1)  # 强制下一帧重算


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
