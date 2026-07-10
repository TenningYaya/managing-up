#camera_2d.gd
extends Camera2D

var dragging = false
var last_mouse_pos = Vector2.ZERO

# 🌟 开局/改比例时,相机水平对准 droparea 之后再加这个偏移(可在 Inspector 里调):
#    > 0 → 相机右移(droparea 在屏幕上偏左);< 0 → 相机左移(droparea 偏右)。
@export var center_x_offset: float = -200.0

# 🌟 将你场景的实际内容宽度和最左边界设为常量，方便统一管理
const BOUND_LEFT := -1500.0
const BOUND_RIGHT := 3580.0

# —— 拖拽员工时的边缘滚动 ——
# 拖着员工把鼠标推到屏幕最左/最右边缘并停留一小会，地图就朝那个方向滚动
@export var edge_scroll_margin: float = 60.0   # 触发滚动的屏幕边缘宽度(像素)
@export var edge_scroll_dwell: float = 0.3     # 需在边缘停留多久才开始滚动(秒)
@export var edge_scroll_speed: float = 800.0   # 滚动速度(世界像素/秒)

var _edge_dwell_left: float = 0.0
var _edge_dwell_right: float = 0.0

func _ready() -> void:
	add_to_group("main_camera")   # 供存档系统按组找到本相机
	# 🌟 监听窗口/视口尺寸变化:比例一变就重新把 droparea 拉回水平居中
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	# 开局水平对准 droparea(用 call_deferred 等容器布局完成后再算,否则取到的位置不准)
	call_deferred("_center_x_on_drop_area")

func _on_viewport_size_changed() -> void:
	_center_x_on_drop_area()

# 🌟 把相机水平对准 droparea → 任何屏幕比例下 droparea 都水平居中。
#    极端比例(视野比场景还宽,比如 50%)时会被下面的边界夹取拉回,允许不完全居中。
func _center_x_on_drop_area() -> void:
	# 读档恢复视角：只要存档里带了相机位置（且玩家还没自己拖过），就恢复到那儿、不居中。
	# 放在这里能天然对抗启动时的多次"尺寸变化重新居中"——每次都恢复，直到玩家接管。
	if Gamemanager.has_saved_camera:
		position = Gamemanager.camera_pos
		_clamp_camera_position()
		return
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
				Gamemanager.has_saved_camera = false   # 玩家开始自己拖视角 = 接管，取消"锁定存档视角"
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


# =====================================================
# 拖拽员工时：鼠标停在屏幕左/右边缘，地图朝该方向滚动
# =====================================================
func _process(delta: float) -> void:
	_update_edge_scroll(delta)

func _update_edge_scroll(delta: float) -> void:
	# 只有正在拖拽某个员工时才启用
	var emp := _get_dragging_employee()
	if emp == null:
		_edge_dwell_left = 0.0
		_edge_dwell_right = 0.0
		return

	# 教程限制：与中键拖拽一致，未完成教程且没拿到通行证时不许滚动
	if not Gamemanager.is_tutorial_completed and not Gamemanager.tutorial_allow_camera_drag:
		return

	var vp_width := get_viewport_rect().size.x
	var mouse_x := get_viewport().get_mouse_position().x

	# 判定鼠标在哪个边缘，并累计停留时间；离开边缘则清零
	var dir := 0
	if mouse_x <= edge_scroll_margin:
		_edge_dwell_left += delta
		_edge_dwell_right = 0.0
		if _edge_dwell_left >= edge_scroll_dwell:
			dir = -1
	elif mouse_x >= vp_width - edge_scroll_margin:
		_edge_dwell_right += delta
		_edge_dwell_left = 0.0
		if _edge_dwell_right >= edge_scroll_dwell:
			dir = 1
	else:
		_edge_dwell_left = 0.0
		_edge_dwell_right = 0.0

	if dir != 0:
		position.x += dir * edge_scroll_speed * delta / zoom.x
		_clamp_camera_position()
		Gamemanager.has_saved_camera = false   # 边缘滚动也算玩家移动了视角，取消存档视角锁定
		# 相机滚动后，被拖的员工靠它自己的 _process 每帧重新贴住光标

# 返回当前正在被拖拽的员工（没有则返回 null）
func _get_dragging_employee() -> Node:
	for e in get_tree().get_nodes_in_group("employees"):
		if e.get("dragging") == true:
			return e
	return null
