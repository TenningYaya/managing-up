# tutorial_blocker_test.gd
extends Control

var target_button: Control 
@onready var finish_label: Label = $"../FinishLabel"

# 动态生成的四块幕布
var curtain_top: ColorRect
var curtain_bottom: ColorRect
var curtain_left: ColorRect
var curtain_right: ColorRect

var hole_rect: Rect2 = Rect2()
var is_tutorial_finished: bool = false
var mask_color = Color(0, 0, 0, 0.5) # 幕布颜色：75%的不透明纯黑

func start_button_tutorial() -> void:
	if finish_label:
		finish_label.hide()
		
	_create_curtains()
	
	await get_tree().process_frame
	
	target_button = get_tree().get_first_node_in_group("recruitment_button")
	
	if target_button:
		hole_rect = target_button.get_global_rect()
		target_button.pressed.connect(_on_target_button_pressed)
		_arrange_curtains(hole_rect)
		
		# 别忘了把自己显示出来
		show() 
	else:
		printerr("糟糕！没找到招聘按钮，请检查 Group 名字！")

# ==========================================
# 核心逻辑 1：用代码实时生成 4 块黑布
# ==========================================
func _create_curtains() -> void:
	curtain_top = _spawn_color_rect("CurtainTop")
	curtain_bottom = _spawn_color_rect("CurtainBottom")
	curtain_left = _spawn_color_rect("CurtainLeft")
	curtain_right = _spawn_color_rect("CurtainRight")

func _spawn_color_rect(rect_name: String) -> ColorRect:
	var cr = ColorRect.new()
	cr.name = rect_name
	cr.color = mask_color
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE # 纯视觉，不挡点击，点击拦截由父节点负责
	add_child(cr)
	return cr

# ==========================================
# 核心逻辑 2：算坐标，把按钮周围围起来
# ==========================================
func _arrange_curtains(rect: Rect2) -> void:
	var screen_size = get_viewport_rect().size
	
	# 上幕布：从屏幕最顶端，盖到按钮的顶端
	curtain_top.global_position = Vector2(0, 0)
	curtain_top.size = Vector2(screen_size.x, rect.position.y)
	
	# 下幕布：从按钮的底端，盖到屏幕最底端
	curtain_bottom.global_position = Vector2(0, rect.end.y)
	curtain_bottom.size = Vector2(screen_size.x, screen_size.y - rect.end.y)
	
	# 左幕布：夹在上下幕布之间，从屏幕最左边，盖到按钮左边
	curtain_left.global_position = Vector2(0, rect.position.y)
	curtain_left.size = Vector2(rect.position.x, rect.size.y)
	
	# 右幕布：夹在上下幕布之间，从按钮右边，盖到屏幕最右边
	curtain_right.global_position = Vector2(rect.end.x, rect.position.y)
	curtain_right.size = Vector2(screen_size.x - rect.end.x, rect.size.y)

# ==========================================
# 核心逻辑 3：点击穿透与全屏拦截
# ==========================================
func _has_point(point: Vector2) -> bool:
	if is_tutorial_finished:
		return true # 教程结束后，拦死全屏
		
	var global_mouse_pos = global_position + point
	
	# 如果鼠标点在了那个没有幕布的“真空洞”里，放行！让底层按钮收到点击！
	if hole_rect.has_point(global_mouse_pos):
		return false
		
	return true # 点在幕布上，拦死

func _on_target_button_pressed() -> void:
	if is_tutorial_finished: return 
	print("第一阶段成功：按钮被点透了！")
	is_tutorial_finished = true
	
	# 按钮按完后，把那个洞也填上（让上下左右幕布闭合，或者直接铺满）
	_close_the_hole()
	
	if finish_label:
		finish_label.show()

func _close_the_hole() -> void:
	var screen_size = get_viewport_rect().size
	curtain_top.size = screen_size # 上幕布直接拉满全屏
	curtain_bottom.hide()
	curtain_left.hide()
	curtain_right.hide()

func _gui_input(event: InputEvent) -> void:
	if is_tutorial_finished and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			print("第二阶段成功：全屏自毁！")
			get_parent().queue_free()
