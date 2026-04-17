extends Control

# --- 设置参数 ---
@export var open_x: float = 1500  # 展开时的 X 坐标
@export var close_x: float = 1780 # 收起时的 X 坐标

var is_open: bool = false         # 记录当前状态
var last_clicked_button: BaseButton = null # 记录上一次点的是哪个按钮

# --- 获取页面引用 ---
# 注意：这里的路径必须和你场景树里的名字完全一样
@onready var content_container = $Content
@onready var settings_page = $Content/SettingsPage
@onready var updates_page = $Content/UpgradesPage
@onready var recruitment_page = $Content/RecruitmentPanel

func _ready():
	# 初始时，菜单躲在屏幕右侧
	position.x = close_x
	is_open = false
	# 初始时隐藏所有具体页面
	hide_all_pages()

# --- 按钮信号连接 ---
func _on_general_pressed():
	# 目前 General 还没做页面，我们先只切换菜单状态
	handle_tab_click($HBoxContainer/VBoxContainer2/General, null)

func _on_hire_pressed():
	handle_tab_click($HBoxContainer/VBoxContainer2/Hire, recruitment_page)

func _on_upgrades_pressed():
	handle_tab_click($HBoxContainer/VBoxContainer2/Upgrades, updates_page)

func _on_settings_pressed():
	# 点击设置时，传入设置页面
	handle_tab_click($HBoxContainer/VBoxContainer2/Settings, settings_page)

func _on_tutorial_pressed():
	handle_tab_click($HBoxContainer/VBoxContainer/Tutorial, null)

func _on_warehouse_pressed():
	handle_tab_click($HBoxContainer/VBoxContainer/warehouse, null)


# --- 核心逻辑函数 ---
func handle_tab_click(current_button: BaseButton, target_page: Control):
	if not is_open:
		# 如果是关着的，就打开并显示页面
		show_page(target_page)
		toggle_menu(true)
		last_clicked_button = current_button
	else:
		# 如果是开着的
		if last_clicked_button == current_button:
			# 点的是同一个按钮，就关上
			toggle_menu(false)
			last_clicked_button = null
			current_button.button_pressed = false 
		else:
			# 点的是不同的按钮，切换页面内容，保持菜单打开
			show_page(target_page)
			last_clicked_button = current_button

func show_page(page: Control):
	hide_all_pages()
	if page:
		page.visible = true

func hide_all_pages():
	# 以后有了其他页面，也要在这里加一句隐藏代码
	settings_page.visible = false
	updates_page.visible = false
	recruitment_page.visible = false

func toggle_menu(should_open: bool):
	is_open = should_open
	var target_x = open_x if is_open else close_x
	var tween = create_tween()
	tween.tween_property(self, "position:x", target_x, 0.3).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

# --- 点击外部收起 ---
func _input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and is_open:
		if not get_global_rect().has_point(event.global_position):
			toggle_menu(false)
			if last_clicked_button:
				last_clicked_button.button_pressed = false
				last_clicked_button = null
