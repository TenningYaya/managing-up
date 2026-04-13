extends Control

# --- 设置参数 ---
@export var open_x: float = 1570  # 展开时的 X 坐标
@export var close_x: float = 1840 # 收起时的 X 坐标

var is_open: bool = false         # 记录当前状态
var last_clicked_button: BaseButton = null # 记录上一次点的是哪个按钮

# --- 初始化 ---
func _ready():
	# 游戏开始时，确保菜单在关闭位置
	position.x = close_x
	is_open = false

# --- 按钮点击处理逻辑 ---
func _on_general_pressed():
	handle_tab_click($VBoxContainer/General)

func _on_hire_pressed():
	handle_tab_click($VBoxContainer/Hire)

func _on_upgrades_pressed():
	handle_tab_click($VBoxContainer/Upgrades)

func _on_settings_pressed():
	handle_tab_click($VBoxContainer/Settings)

# 通用的点击处理函数
func handle_tab_click(current_button: BaseButton):
	if not is_open:
		# 如果菜单是关着的，点任何按钮都打开
		toggle_menu(true)
		last_clicked_button = current_button
	else:
		# 如果菜单是开着的
		if last_clicked_button == current_button:
			# 如果点的是同一个按钮，就关上菜单
			toggle_menu(false)
			last_clicked_button = null
			# 取消按钮的选中状态（让它弹起来）
			current_button.button_pressed = false 
		else:
			# 如果点的是不同的按钮，保持打开，只更新记录
			last_clicked_button = current_button

# --- 核心动画函数 ---
func toggle_menu(should_open: bool):
	is_open = should_open
	var target_x = open_x if is_open else close_x
	
	var tween = create_tween()
	tween.tween_property(self, "position:x", target_x, 0.3).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

# --- 点击外部收起逻辑 ---
func _input(event: InputEvent):
	# 如果玩家点了一下鼠标左键，且菜单是开着的
	if event is InputEventMouseButton and event.pressed and is_open:
		# 检查鼠标点击的位置是否在菜单的“全局矩形区域”之外
		if not get_global_rect().has_point(event.global_position):
			toggle_menu(false)
			# 如果收起了，记得把所有按钮的按下状态清空
			if last_clicked_button:
				last_clicked_button.button_pressed = false
				last_clicked_button = null
				
