extends Control

# =====================================================
# 1. Sidebar 展开 / 收回相关节点
# =====================================================
@onready var phone_wrapper: Control = $PhoneWrapper
@onready var trigger_btn: BaseButton = $Trigger


var is_open := false

# 根据你之前测试好的坐标
var open_x := -213.0
var closed_x := 253.0

var _is_locked_by_tutorial := false # 记录当前是否处于“教程霸体”状态
var _flash_tween: Tween             # 用来存图标闪烁的动画，方便后续停掉

# =====================================================
# 2. 手机首页 / App 页面区域
# =====================================================
@onready var home_screen: Control = $PhoneWrapper/Screen/HomeScreen
@onready var app_display_area: Control = $PhoneWrapper/Screen/AppDisplayArea

# App 图标按钮
@onready var btn_general: BaseButton = $PhoneWrapper/Screen/HomeScreen/CenterContainer/GridContainer/general
@onready var btn_settings: BaseButton = $PhoneWrapper/Screen/HomeScreen/CenterContainer/GridContainer/settings
@onready var btn_upgrades: BaseButton = $PhoneWrapper/Screen/HomeScreen/CenterContainer/GridContainer/upgrades
@onready var btn_tutorial: BaseButton = $PhoneWrapper/Screen/HomeScreen/CenterContainer/GridContainer/tutorial

# 手机底部 Home / Back 按钮
@onready var home_button: BaseButton = $PhoneWrapper/HomeButton

# App 页面
@onready var general_page: Control = $PhoneWrapper/Screen/AppDisplayArea/GeneralPage
@onready var settings_page: Control = $PhoneWrapper/Screen/AppDisplayArea/SettingsPage
@onready var upgrades_page: Control = $PhoneWrapper/Screen/AppDisplayArea/UpgradesPage
@onready var tutorial_page: Control = $PhoneWrapper/Screen/AppDisplayArea/TutorialPage

# 如果你之后做了 TutorialPage，就取消这行注释
# @onready var tutorial_page: Control = $PhoneWrapper/Screen/AppDisplayArea/TutorialPage


func _ready() -> void:
	# =====================================================
	# 初始状态：手机收回
	# =====================================================
	phone_wrapper.position.x = closed_x

	trigger_btn.show()
	is_open = false

	# 初始状态：显示手机桌面
	show_home_screen()

	# =====================================================
	# 连接 Sidebar 展开 / 收回按钮
	# =====================================================
	trigger_btn.pressed.connect(open_phone)


	# =====================================================
	# 连接 App 图标按钮
	# =====================================================
	btn_general.pressed.connect(func():
		open_app(general_page)
	)

	btn_settings.pressed.connect(func():
		open_app(settings_page)
	)

	btn_upgrades.pressed.connect(func():
		open_app(upgrades_page)
	)

	btn_tutorial.pressed.connect(func():
		print("Tutorial app clicked, but TutorialPage is not ready yet.")
		# 如果你之后有 TutorialPage，就改成：
		# open_app(tutorial_page)
	)

	# =====================================================
	# 手机底部按钮：返回桌面
	# =====================================================
	home_button.pressed.connect(show_home_screen)

func _input(event: InputEvent) -> void:
	# 1. 如果手机本来就是关着的，雷达不工作
	if not is_open: 
		return

	# 2. 捕捉全屏的鼠标左键按下事件
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		
		# 3. 拿到手机【真正机身】的物理矩形！
		# 注意：这里千万别拿 CloseBlocker，要拿装手机内容的那个节点，比如 PhoneWrapper！
		var phone_rect = $PhoneWrapper.get_global_rect()
		
		# 4. 如果鼠标点的坐标，不在手机机身范围内
		if not phone_rect.has_point(event.global_position):
			# 直接调用你原本收手机的函数（就是原来 CloseBlocker 的 pressed 连的那个函数）
			close_phone() 
			
			# 注意！千万不要写 get_viewport().set_input_as_handled()！
			# 这样点击事件就能像幽灵一样穿透下去，精准砸中外面的按钮！
			
# =====================================================
# 3. 展开手机
# =====================================================
func open_phone() -> void:
	if is_open:
		return

	is_open = true

	trigger_btn.hide()


	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(phone_wrapper, "position:x", open_x, 0.5)


# =====================================================
# 4. 收回手机
# =====================================================
func close_phone() -> void:
	if _is_locked_by_tutorial:
		print("【教程锁死】KPI宝拒绝关闭手机！")
		return
		
	if not is_open:
		return

	is_open = false



	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(phone_wrapper, "position:x", closed_x, 0.5)

	tween.finished.connect(func():
		if not is_open:
			trigger_btn.show()
	)


# =====================================================
# 5. 打开某个 App 页面
# =====================================================
func open_app(page: Control) -> void:
	hide_all_pages()

	home_screen.visible = false
	app_display_area.visible = true
	page.visible = true


# =====================================================
# 6. 返回手机桌面
# =====================================================
func show_home_screen() -> void:
	hide_all_pages()

	home_screen.visible = true
	app_display_area.visible = false


# =====================================================
# 7. 隐藏所有 App 页面
# =====================================================
func hide_all_pages() -> void:
	general_page.visible = false
	settings_page.visible = false
	upgrades_page.visible = false

	# 如果你之后有 TutorialPage，就取消这行注释
	# tutorial_page.visible = false

func lock_for_tutorial() -> void:
	_is_locked_by_tutorial = true
	
	# 1. 如果手机现在是收起来的，强行调你的原函数把它弹出来
	if not is_open:
		open_phone()

func unlock_from_tutorial() -> void:
	_is_locked_by_tutorial = false

	btn_tutorial.modulate.a = 1.0
