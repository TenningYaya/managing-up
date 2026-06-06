#camera_2d.gd
extends Camera2D

var dragging = false
var last_mouse_pos = Vector2.ZERO

#func _input(event: InputEvent) -> void:
	## 1. 判定按下中键（或者左键，你可以根据需求改）
	#if event is InputEventMouseButton:
		#if event.button_index == MOUSE_BUTTON_MIDDLE:
			#if event.pressed:
				#if not Gamemanager.is_tutorial_completed:
					#dragging = false
					#return # 拦截按下事件
					#
				#dragging = true
				#last_mouse_pos = event.global_position
			#else:
				#dragging = false
#
	## 2. 拖拽逻辑
	#if event is InputEventMouseMotion and dragging:
		#if not Gamemanager.is_tutorial_completed:
			#dragging = false
			#return
			#
		#var delta = event.global_position - last_mouse_pos
		#position -= delta # 注意是减法，鼠标往右拽，相机往左走，画面就往右平移
		#position.x = clamp(position.x, -100, 2110) # 添加camera的限制范围
		#last_mouse_pos = event.global_position

func _input(event: InputEvent) -> void:
	# 1. 判定按下中键
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				# 🌟 核心修改：如果是没通关，且没拿到特权通行证，才拦截
				if not Gamemanager.is_tutorial_completed and not Gamemanager.tutorial_allow_camera_drag:
					dragging = false
					return 
					
				dragging = true
				last_mouse_pos = event.global_position
			else:
				dragging = false

	# 2. 拖拽逻辑
	if event is InputEventMouseMotion and dragging:
		# 🌟 核心修改：同样加上通行证判断
		if not Gamemanager.is_tutorial_completed and not Gamemanager.tutorial_allow_camera_drag:
			dragging = false
			return
			
		var delta = event.global_position - last_mouse_pos
		position -= delta 
		position.x = clamp(position.x, -100, 2110) 
		last_mouse_pos = event.global_position
