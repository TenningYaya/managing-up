extends Control

# --- 1. 变量定义 ---
var is_sticky := false
var original_size := Vector2i(1920, 360) # 请根据你实际的大窗口尺寸修改

# 伪 StickyNote 的尺寸和边距
const STICKY_SIZE := Vector2(270, 360)
const STICKY_MARGIN := Vector2(10, 10)

# --- 2. Initialization (初始化) ---
func _ready():
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	get_viewport().transparent_bg = true
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)

	_show_normal_mode_immediately()

	print("window mode: ", DisplayServer.window_get_mode())
	print("window size: ", DisplayServer.window_get_size())


# --- 3. 输入监听 ---
func _input(event):
	if event.is_action_pressed("toggle_sticky_mode"):
		toggle_mode()


# --- 4. 模式切换逻辑 ---
func toggle_mode():
	is_sticky = !is_sticky

	if is_sticky:
		enter_sticky_mode()
	else:
		exit_sticky_mode()


func enter_sticky_mode():
	# 隐藏正常游戏模式整组
	$FullGameMode.hide()
	$CanvasLayer.hide()

	# 显示 StickyNote
	$StickyNote.show()

	# 等一帧，让布局稳定
	await get_tree().process_frame

	# 用当前窗口实时大小来算右下角位置，更稳
	var win_size = DisplayServer.window_get_size()

	# 让 StickyNote 固定尺寸，并放在窗口内部右下角
	$StickyNote.set_anchors_preset(Control.PRESET_TOP_LEFT)
	$StickyNote.size = STICKY_SIZE
	$StickyNote.position = Vector2(
		win_size.x - STICKY_SIZE.x - STICKY_MARGIN.x,
		win_size.y - STICKY_SIZE.y - STICKY_MARGIN.y
	)
	$StickyNote.scale = Vector2.ONE
	$StickyNote.modulate = Color(1, 1, 1, 1)

	# 只允许点击 StickyNote 区域
	update_mouse_passthrough($StickyNote)

	print("进入伪 StickyNote 模式")
	print("StickyNote visible: ", $StickyNote.visible)
	print("StickyNote position: ", $StickyNote.position)
	print("StickyNote size: ", $StickyNote.size)
	print("StickyNote rect: ", $StickyNote.get_global_rect())


func exit_sticky_mode():
	# 隐藏 StickyNote
	$StickyNote.hide()

	# 显示正常模式整组
	$FullGameMode.show()
	$CanvasLayer.show()

	# 恢复 FullGameMode 铺满
	$FullGameMode.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$FullGameMode.position = Vector2.ZERO
	$FullGameMode.scale = Vector2.ONE
	$FullGameMode.modulate = Color(1, 1, 1, 1)

	# 正常模式下整个窗口都可点击
	set_full_window_clickable()

	print("切回游戏模式")
	print("FullGameMode visible: ", $FullGameMode.visible)
	print("CanvasLayer visible: ", $CanvasLayer.visible)
	print("StickyNote visible: ", $StickyNote.visible)
	print("FullGameMode rect: ", $FullGameMode.get_global_rect())


# --- 初始直接显示正常模式 ---
func _show_normal_mode_immediately():
	$StickyNote.hide()
	$FullGameMode.show()
	$CanvasLayer.show()

	$FullGameMode.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$FullGameMode.position = Vector2.ZERO
	$FullGameMode.scale = Vector2.ONE
	$FullGameMode.modulate = Color(1, 1, 1, 1)

	set_full_window_clickable()


# --- 通用辅助函数：按某个节点设置可点击区域 ---
func update_mouse_passthrough(target_node: Control):
	await get_tree().process_frame

	var rect = target_node.get_global_rect()

	var region_points = PackedVector2Array([
		Vector2(rect.position.x, rect.position.y), # 左上
		Vector2(rect.position.x + rect.size.x, rect.position.y), # 右上
		Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y), # 右下
		Vector2(rect.position.x, rect.position.y + rect.size.y) # 左下
	])

	DisplayServer.window_set_mouse_passthrough(region_points)


# --- 正常模式：整个窗口都可点击 ---
func set_full_window_clickable():
	var win_size = DisplayServer.window_get_size()

	var points = PackedVector2Array([
		Vector2(0, 0),
		Vector2(win_size.x, 0),
		Vector2(win_size.x, win_size.y),
		Vector2(0, win_size.y)
	])

	DisplayServer.window_set_mouse_passthrough(points)


# --- 保留你原来的辅助函数 ---
func set_clickable_area_by_node(node: Control):
	var rect = node.get_global_rect()

	var points = PackedVector2Array()
	points.push_back(Vector2(rect.position.x, rect.position.y)) # 左上
	points.push_back(Vector2(rect.position.x + rect.size.x, rect.position.y)) # 右上
	points.push_back(Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y)) # 右下
	points.push_back(Vector2(rect.position.x, rect.position.y + rect.size.y)) # 左下

	DisplayServer.window_set_mouse_passthrough(points)
