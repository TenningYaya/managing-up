extends Control

# --- 1. 变量定义 ---
var is_sticky = false
var original_window_pos = Vector2i()
var original_size = Vector2i(1920, 360) # 请根据你实际的大窗口尺寸修改

# 拖拽相关变量
var is_dragging = false
var mouse_offset = Vector2i()

# --- 2. Initialization (初始化) ---
func _ready():
	
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	# 开启透明背景
	get_viewport().transparent_bg = true
	
	# 移除窗口边框
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	
	# 初始状态显示大游戏界面，隐藏便利贴
	$FullGameMode.show()
	$StickyNote.hide()
	
	print("window mode: ", DisplayServer.window_get_mode())

# --- 3. 输入监听 ---
func _input(event):
	# 监听快捷键 (需在 Input Map 设置 toggle_sticky_mode)
	if event.is_action_pressed("toggle_sticky_mode"):
		toggle_mode()
	
	# 只有在便利贴模式下才处理拖拽
	if is_sticky:
		handle_drag(event)

# --- 4. 模式切换逻辑 ---
func toggle_mode():
	is_sticky = !is_sticky
	
	if is_sticky:
		# --- 进入便利贴模式 ---
		# 记录当前窗口在屏幕上的 Coordinates (坐标)
		original_window_pos = DisplayServer.window_get_position()
		
		# 界面切换
		$FullGameMode.hide()
		$StickyNote.show()
		
		# 缩小窗口并置顶
		DisplayServer.window_set_size(Vector2i(270, 360))
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	else:
		# --- 回到游戏模式 ---
		$StickyNote.hide()
		$FullGameMode.show()
		
		# 恢复尺寸、位置并取消置顶
		DisplayServer.window_set_size(original_size)
		DisplayServer.window_set_position(original_window_pos)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)

# --- 5. 窗口拖拽逻辑 ---
func handle_drag(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# 鼠标按下，开始拖拽
				is_dragging = true
				# 计算鼠标相对于窗口左上角的偏移
				var mouse_pos = DisplayServer.mouse_get_position()
				var window_pos = DisplayServer.window_get_position()
				mouse_offset = mouse_pos - window_pos
			else:
				# 鼠标松开
				is_dragging = false
				
	if event is InputEventMouseMotion and is_dragging:
		# 实时更新窗口在屏幕上的位置
		var current_mouse_pos = DisplayServer.mouse_get_position()
		DisplayServer.window_set_position(current_mouse_pos - mouse_offset)
