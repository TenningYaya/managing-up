#camera_2d.gd
extends Camera2D

var dragging = false
var last_mouse_pos = Vector2.ZERO

# 🌟 开局/改比例时,相机水平对准 droparea 之后再加这个偏移(可在 Inspector 里调):
#    > 0 → 相机右移(droparea 在屏幕上偏左);< 0 → 相机左移(droparea 偏右)。
@export var center_x_offset: float = -200.0

# 🌟 将你场景的实际内容宽度和最左边界设为常量，方便统一管理
const BOUND_LEFT := -1000.0
const BOUND_RIGHT := 3060.0

func _ready() -> void:
	# 🌟 监听窗口/视口尺寸变化:比例一变就重新把 droparea 拉回水平居中
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	# 开局水平对准 droparea(用 call_deferred 等容器布局完成后再算,否则取到的位置不准)
	call_deferred("_center_x_on_drop_area")

func _on_viewport_size_changed() -> void:
	_center_x_on_drop_area()

# 🌟 把相机水平对准 droparea → 任何屏幕比例下 droparea 都水平居中。
#    极端比例(视野比场景还宽,比如 50%)时会被下面的边界夹取拉回,允许不完全居中。
func _center_x_on_drop_area() -> void:
	var da = get_tree().get_first_node_in_group("employee_droparea")
	if da and da is Control:
		position.x = da.get_global_rect().get_center().x + center_x_offset
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
