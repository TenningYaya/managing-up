##camera_2d.gd
#extends Camera2D
#
#var dragging = false
#var last_mouse_pos = Vector2.ZERO
#
##func _input(event: InputEvent) -> void:
	### 1. 判定按下中键（或者左键，你可以根据需求改）
	##if event is InputEventMouseButton:
		##if event.button_index == MOUSE_BUTTON_MIDDLE:
			##if event.pressed:
				##if not Gamemanager.is_tutorial_completed:
					##dragging = false
					##return # 拦截按下事件
					##
				##dragging = true
				##last_mouse_pos = event.global_position
			##else:
				##dragging = false
##
	### 2. 拖拽逻辑
	##if event is InputEventMouseMotion and dragging:
		##if not Gamemanager.is_tutorial_completed:
			##dragging = false
			##return
			##
		##var delta = event.global_position - last_mouse_pos
		##position -= delta # 注意是减法，鼠标往右拽，相机往左走，画面就往右平移
		##position.x = clamp(position.x, -100, 2110) # 添加camera的限制范围
		##last_mouse_pos = event.global_position
#
#func _input(event: InputEvent) -> void:
	## 1. 判定按下中键
	#if event is InputEventMouseButton:
		#if event.button_index == MOUSE_BUTTON_MIDDLE:
			#if event.pressed:
				## 🌟 核心修改：如果是没通关，且没拿到特权通行证，才拦截
				#if not Gamemanager.is_tutorial_completed and not Gamemanager.tutorial_allow_camera_drag:
					#dragging = false
					#return 
					#
				#dragging = true
				#last_mouse_pos = event.global_position
			#else:
				#dragging = false
#
	## 2. 拖拽逻辑
	#if event is InputEventMouseMotion and dragging:
		## 🌟 核心修改：同样加上通行证判断
		#if not Gamemanager.is_tutorial_completed and not Gamemanager.tutorial_allow_camera_drag:
			#dragging = false
			#return
			#
		#var delta = event.global_position - last_mouse_pos
		#position -= delta 
		#position.x = clamp(position.x, -100, 2110) 
		#last_mouse_pos = event.global_position

extends Camera2D

var dragging = false
var last_mouse_pos = Vector2.ZERO

# 🌟 将你场景的实际内容宽度和最左边界设为常量，方便统一管理
#const CONTENT_WIDTH := 2210.0 # 场景总宽度 (原 2110 - (-100) 的绝对值)
#const MIN_X := -100.0         # 相机能到达的最左侧坐标
#const CONTENT_WIDTH := 3980.0 # 场景总宽度 (原 2110 - (-100) 的绝对值)
#const MIN_X := 100.0         # 相机能到达的最左侧坐标
const BOUND_LEFT := -1000.0
const BOUND_RIGHT := 3060.0

func _ready() -> void:
	# 🌟 核心新增：监听窗口/视口尺寸变化的信号
	# 这样当你同学的 settings_page 触发分辨率改变时，相机会自动校准，防止露出界外黑边
	get_viewport().size_changed.connect(_on_viewport_size_changed)

func _on_viewport_size_changed() -> void:
	# 窗口大小改变时，立刻重新计算并限制相机位置
	_clamp_camera_position()

func _input(event: InputEvent) -> void:
	# 1. 判定按下中键
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				# 拦截未完成教程且没拿到通行证的情况
				if not Gamemanager.is_tutorial_completed and not Gamemanager.tutorial_allow_camera_drag:
					dragging = false
					return 
					
				dragging = true
				last_mouse_pos = event.global_position
			else:
				dragging = false

	# 2. 拖拽逻辑
	if event is InputEventMouseMotion and dragging:
		if not Gamemanager.is_tutorial_completed and not Gamemanager.tutorial_allow_camera_drag:
			dragging = false
			return
			
		var delta = event.global_position - last_mouse_pos
		position -= delta 
		
		# 🌟 调用统一的边界限制函数
		_clamp_camera_position()
		
		last_mouse_pos = event.global_position

## 🌟 核心算法：根据当前屏幕的实时宽度，计算相机的最大拖动范围
#func _clamp_camera_position() -> void:
	## 获取当前摄像机真实看到的视野宽度（除以 zoom 是为了兼容以后可能加的视野缩放功能）
	#var visible_width = get_viewport_rect().size.x / zoom.x
	#
	## 如果玩家屏幕特别长，比你画的场景贴图还要长，那就直接把相机锁死在最左侧
	#if visible_width >= CONTENT_WIDTH:
		#position.x = MIN_X 
	#else:
		## 动态计算最右侧能拖到哪里：起点 + (总内容长度 - 屏幕当前能看多长)
		#var max_x = MIN_X + (CONTENT_WIDTH - visible_width)
		#
		## 限制相机 X 坐标不超标
		#position.x = clamp(position.x, MIN_X, max_x)
		
func _clamp_camera_position() -> void:
	# 获取当前摄像机真实看到的视野宽度
	var visible_width = get_viewport_rect().size.x / zoom.x
	# 算出半个屏幕的宽度，这是留给中心点的“缓冲垫”
	var half_width = visible_width / 2.0 
	
	# 场景的实际总宽度
	var content_width = BOUND_RIGHT - BOUND_LEFT
	
	# 极端情况兜底：如果玩家的屏幕超级宽（或者窗口拉得极长），比你做的游戏场景还要宽
	if visible_width >= content_width:
		# 直接把相机锁死在场景的最正中间，两边留黑边，不允许拖动
		position.x = BOUND_LEFT + content_width / 2.0
	else:
		# 🌟 真正正确的限制公式：中心点必须远离空气墙“半个屏幕”的距离
		var min_cam_x = BOUND_LEFT + half_width
		var max_cam_x = BOUND_RIGHT - half_width
		
		# 限制相机中心点在这两个安全坐标之间滑动
		position.x = clamp(position.x, min_cam_x, max_cam_x)
