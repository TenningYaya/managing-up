extends CanvasLayer

signal confirmed
# 当这个对话框显示出来时，我们确保它能接收到点击

var _main_ref: Node = null  # 主场景 Main，用于临时关闭鼠标穿透裁剪

# 本对话框是“居中弹出的 CanvasLayer”，出现在底部条之外。
# 必须临时让整屏可见，否则在 Windows 上会被 region 裁掉、根本看不见（这就是“弹不出来”的原因）。
func _ready() -> void:
	_main_ref = get_tree().current_scene
	if is_instance_valid(_main_ref) and _main_ref.has_method("suppress_passthrough"):
		_main_ref.suppress_passthrough(true)

# 关闭时（确定退出 / 取消 / 点背景）统一恢复穿透
func _exit_tree() -> void:
	if is_instance_valid(_main_ref) and _main_ref.has_method("suppress_passthrough"):
		_main_ref.suppress_passthrough(false)

# --- 1. 点击“确定”：直接退出游戏 ---
func _on_confirm_button_pressed():
	confirmed.emit()
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
