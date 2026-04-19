extends Camera2D

var dragging = false
var last_mouse_pos = Vector2.ZERO

func _input(event: InputEvent) -> void:
	# 1. 判定按下中键（或者左键，你可以根据需求改）
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				dragging = true
				last_mouse_pos = event.global_position
			else:
				dragging = false

	# 2. 拖拽逻辑
	if event is InputEventMouseMotion and dragging:
		# 计算鼠标移动了多少，然后反向移动相机
		var delta = event.global_position - last_mouse_pos
		position -= delta # 注意是减法，鼠标往右拽，相机往左走，画面就往右平移
		last_mouse_pos = event.global_position
