extends Control

# 当这个对话框显示出来时，我们确保它能接收到点击
func _ready():
	# 确保根节点的鼠标过滤是 Stop，这样它才能“感觉到”点击
	mouse_filter = Control.MOUSE_FILTER_STOP

# --- 1. 点击“确定”：直接退出游戏 ---
func _on_confirm_button_pressed():
	get_tree().quit()

# --- 2. 点击“取消”：销毁对话框 ---
func _on_cancel_button_pressed():
	queue_free()

# --- 3. 点击“背景”：也视为取消 ---
# 这个函数专门处理这个根节点（1920*360区域）收到的输入信号
func _gui_input(event):
	# 如果玩家按下了鼠标左键
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 我们就执行销毁，让对话框消失
		queue_free()
