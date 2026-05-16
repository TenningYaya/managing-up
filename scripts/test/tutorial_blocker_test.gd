# tutorial_blocker_test.gd
extends ColorRect

var target_button: Control 
@onready var finish_label: Label = $"../FinishLabel"

var hole_rect: Rect2 = Rect2()
var is_tutorial_finished: bool = false # 标记：是否已经触发了成功提示

func _ready() -> void:
	# 隐藏提示字，防止一上来就穿帮
	if finish_label:
		finish_label.hide()
		
	await get_tree().process_frame
	
	# 🌟 已自动对齐老板最新的组名：recruitment_button
	target_button = get_tree().get_first_node_in_group("recruitment_button")
	
	if target_button:
		hole_rect = target_button.get_global_rect()
		target_button.pressed.connect(_on_target_button_pressed)
		queue_redraw() # 触发下面的 _draw 绘图
	else:
		printerr("糟糕！没找到招聘按钮，请检查 Group 名字！")

# 🌟 核心拦截逻辑：动态调整拦截范围
func _has_point(point: Vector2) -> bool:
	if is_tutorial_finished:
		return true # 点完按钮后，全屏重新拦截，用来捕获接下来的“任意点击”
		
	if hole_rect == Rect2():
		return true 
		
	var global_mouse_pos = global_position + point
	if hole_rect.has_point(global_mouse_pos):
		return false # 放行，让玩家能点到按钮
		
	return true # 拦死其他地方

# 🌟 核心绘图逻辑：全宇宙最稳的现场画框代码行
func _draw() -> void:
	if hole_rect != Rect2():
		var local_pos = hole_rect.position - global_position
		var local_rect = Rect2(local_pos, hole_rect.size)
		
		# 🌟 重点修改：利用 RenderingServer 绕过节点自身的 Alpha 调制
		# 或者直接用这个最土但有效的办法：把颜色的数值往上翻倍，强行顶上去
		# 但更标准的姿势是：不要在带有 Alpha 调制的 ColorRect 身上自画，而是交给它的儿子
		draw_rect(local_rect, Color(2.0, 2.0, 2.0, 1.0), false, 3.0)

# 当按钮被点透时触发（进入第二阶段）
func _on_target_button_pressed() -> void:
	if is_tutorial_finished: return # 防止重复触发
	
	print("第一阶段成功：按钮被点透了！")
	is_tutorial_finished = true
	
	# 1. 弹出提示字
	if finish_label:
		finish_label.show()
	
	# 🌟 已经重锤修正：删除了以前清空 hole_rect 和 queue_redraw 的坑爹代码！
	# 让白框在玩家按完按钮后，死死钉在原地陪着提示字，绝不乱跑！

# 🌟 第二阶段：捕获全屏幕的任意点击
func _gui_input(event: InputEvent) -> void:
	if is_tutorial_finished and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			print("第二阶段成功：玩家点击了任意地方，教程彻底关闭！")
			
			if finish_label:
				finish_label.hide()
			
			# 绝户计：连根拔起销毁整个 CanvasLayer，黑布、白框、字一起灰飞烟灭！
			get_parent().queue_free()
