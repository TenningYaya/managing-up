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
		original_window_pos = DisplayServer.window_get_position()
		
		$FullGameMode.hide()
		$StickyNote.show()
		$CanvasLayer.hide()
		
		# 1. 调整窗口大小
		var sticky_size = Vector2i(270, 360)
		DisplayServer.window_set_size(sticky_size)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
		
		# 2. 核心改动：把点击区域设置为 StickyNote 的范围
		# 因为窗口现在和节点一样大，所以直接传 0,0 到 270,360 的点
		update_mouse_passthrough($StickyNote)
		
	else:
		# --- 回到游戏模式 ---
		$StickyNote.hide()
		$FullGameMode.show()
		$CanvasLayer.show()
		
		# 1. 恢复窗口
		DisplayServer.window_set_size(original_size)
		DisplayServer.window_set_position(original_window_pos)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)
		
		# 2. 核心改动：把点击区域设置为 FullGameMode 的范围
		update_mouse_passthrough($FullGameMode)

# --- 这是一个通用的辅助函数，不分模式，谁显示就量谁 ---
func update_mouse_passthrough(target_node: Control):
	# 等待一帧，确保节点的大小和位置已经更新完毕
	await get_tree().process_frame
	
	# 量取目标节点在窗口里的矩形范围 (Bounding Box)
	var rect = target_node.get_global_rect()
	
	# 创建一个 Polygon (多边形) 地图
	var region_points = PackedVector2Array([
		Vector2(rect.position.x, rect.position.y), # 左上
		Vector2(rect.position.x + rect.size.x, rect.position.y), # 右上
		Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y), # 右下
		Vector2(rect.position.x, rect.position.y + rect.size.y) # 左下
	])
	
	# 告诉系统：除了这个框框，其他透明的地方都“穿透”过去
	DisplayServer.window_set_mouse_passthrough(region_points)
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

func set_clickable_area_by_node(node: Control):
	# 获取该节点在屏幕上的实时矩形范围 (Bounding Box)
	var rect = node.get_global_rect()
	
	# 根据这个矩形的四个角，自动生成地图点
	var points = PackedVector2Array()
	points.push_back(Vector2(rect.position.x, rect.position.y)) # 左上
	points.push_back(Vector2(rect.position.x + rect.size.x, rect.position.y)) # 右上
	points.push_back(Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y)) # 右下
	points.push_back(Vector2(rect.position.x, rect.position.y + rect.size.y)) # 左下
	
	# 告诉系统：只有这个动态量出来的区域不许穿透
	DisplayServer.window_set_mouse_passthrough(points)
