extends Control

# --- 1. 变量定义 ---
var is_sticky = false
var original_window_pos = Vector2i()
var original_size = Vector2i(1920, 360)

# 拖拽相关变量
var is_dragging = false
var mouse_offset = Vector2i()

# --- 2. Initialization ---
func _ready():
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	get_viewport().transparent_bg = true
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)

	$FullGameMode.show()
	$StickyNote.hide()

	# 👉 初始整个窗口可点击
	set_full_window_clickable()

	print("window mode: ", DisplayServer.window_get_mode())


# --- 3. 输入监听 ---
func _input(event):
	if event.is_action_pressed("toggle_sticky_mode"):
		toggle_mode()

	if is_sticky:
		handle_drag(event)


# --- 4. 模式切换逻辑 ---
func toggle_mode():
	is_sticky = !is_sticky

	if is_sticky:
		enter_sticky_mode()
	else:
		exit_sticky_mode()


func enter_sticky_mode():
	# 记录原始位置
	original_window_pos = DisplayServer.window_get_position()

	# UI切换
	$FullGameMode.hide()
	$StickyNote.show()
	$CanvasLayer.hide()

	# 缩小窗口
	DisplayServer.window_set_size(Vector2i(270, 360))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)

	await get_tree().process_frame

	# 👉 关键：只让 StickyNote 可点击
	update_mouse_passthrough($StickyNote)

	print("进入 Sticky 模式")


func exit_sticky_mode():
	# UI恢复
	$StickyNote.hide()
	$FullGameMode.show()
	$CanvasLayer.show()

	# 窗口恢复
	DisplayServer.window_set_size(original_size)
	DisplayServer.window_set_position(original_window_pos)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)

	await get_tree().process_frame

	# 👉 关键：整个窗口可点击
	set_full_window_clickable()

	print("退出 Sticky 模式")


# --- 5. 拖拽逻辑 ---
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
# ✅ 新增：鼠标穿透核心函数
# ================================

func update_mouse_passthrough(target_node: Control):
	await get_tree().process_frame

	var rect = target_node.get_global_rect()

	var points = PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0),
		rect.position + rect.size,
		rect.position + Vector2(0, rect.size.y)
	])

	DisplayServer.window_set_mouse_passthrough(points)


func set_full_window_clickable():
	var win_size = DisplayServer.window_get_size()

	var points = PackedVector2Array([
		Vector2(0, 0),
		Vector2(win_size.x, 0),
		Vector2(win_size.x, win_size.y),
		Vector2(0, win_size.y)
	])

	DisplayServer.window_set_mouse_passthrough(points)
