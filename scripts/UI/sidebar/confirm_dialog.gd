extends CanvasLayer

signal confirmed
# 当这个对话框显示出来时，我们确保它能接收到点击

var _main_ref: Node = null  # 主场景 Main，用于临时关闭鼠标穿透裁剪
var _message_key: String = ""  # set_texts 传入的本地化键(交给 Label 的 auto_translate 自动翻译)
var _confirm_key: String = ""  # 确定按钮文字的本地化键(留空=保留场景里的默认)
var _cancel_key: String = ""   # 取消按钮文字的本地化键(留空=保留场景里的默认)

# 本对话框是“居中弹出的 CanvasLayer”，出现在底部条之外。
# 必须临时让整屏可见，否则在 Windows 上会被 region 裁掉、根本看不见（这就是“弹不出来”的原因）。
func _ready() -> void:
	_main_ref = get_tree().current_scene
	if is_instance_valid(_main_ref) and _main_ref.has_method("suppress_passthrough"):
		_main_ref.suppress_passthrough(true)
	_apply_texts()

# 由调用方传入"本地化键"(不是翻译后的文本);Label 的 auto_translate 会自动翻成当前语言。
# 注意:settings_page 在 add_child 之前就调用本方法,所以这里用 get_node_or_null 直接取
# (实例化后子节点已存在,无需等 _ready),并在 _ready 里再应用一次做双保险。
func set_texts(message_key: String, confirm_key: String = "", cancel_key: String = "") -> void:
	_message_key = message_key
	_confirm_key = confirm_key
	_cancel_key = cancel_key
	_apply_texts()

func _apply_texts() -> void:
	# 都是"本地化键",由各 Label 的 auto_translate 自动翻成当前语言;留空就保留场景里的默认文字。
	if _message_key != "":
		var lbl := get_node_or_null("Panel/VBoxContainer/Label") as Label
		if lbl:
			lbl.text = _message_key
	if _confirm_key != "":
		var yes := get_node_or_null("Panel/VBoxContainer/HBoxContainer/ConfirmButton/Label") as Label
		if yes:
			yes.text = _confirm_key
	if _cancel_key != "":
		var no := get_node_or_null("Panel/VBoxContainer/HBoxContainer/CancelButton/Label") as Label
		if no:
			no.text = _cancel_key

# 关闭时（确定退出 / 取消 / 点背景）统一恢复穿透
func _exit_tree() -> void:
	if is_instance_valid(_main_ref) and _main_ref.has_method("suppress_passthrough"):
		_main_ref.suppress_passthrough(false)

# --- 1. 点击“确定”：只发信号 + 关闭弹窗，具体做什么交给调用方 ---
# (保存并退出 → 调用方会退游戏；删除存档 → 调用方只删档不退游戏。不再写死 get_tree().quit())
func _on_confirm_button_pressed():
	confirmed.emit()
	queue_free()

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
