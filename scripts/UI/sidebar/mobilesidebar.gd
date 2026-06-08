#mobilesidebar.gd
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

var _is_locked_by_tutorial := false
var _flash_tween: Tween

# =====================================================
# 升级提示（红点 + 震动）相关
# =====================================================
# 玩家升级各级费用（与 upgrades_page.gd 保持一致）
const PLAYER_UPGRADE_COST := {1: 50, 2: 1000, 3: 5000, 4: 15000}

const SHAKE_FREQ := 46.0          # 抖动频率
const SHAKE_AMP := 5.0            # 抖动幅度（像素）
const FIRST_SHAKE_DURATION := 10.0   # 刚出现可升级时抖动持续时间
const REMINDER_SHAKE_DURATION := 5.0 # 周期提醒每次抖动时间
const REMINDER_INTERVAL := 900.0     # 周期提醒间隔（15 分钟）

var _was_upgradable := false      # 上一次判定是否有可升级内容
var _shake_time_left := 0.0       # 剩余抖动时间
var _trigger_home := Vector2.ZERO # Trigger 原始位置
var _reminder_timer: Timer = null

# =====================================================
# 2. 手机首页 / App 页面区域
# =====================================================
@onready var home_screen: Control = $PhoneWrapper/Screen/HomeScreen
@onready var app_display_area: Control = $PhoneWrapper/Screen/AppDisplayArea

@onready var btn_general: BaseButton = $PhoneWrapper/Screen/HomeScreen/CenterContainer/GridContainer/general
@onready var btn_settings: BaseButton = $PhoneWrapper/Screen/HomeScreen/CenterContainer/GridContainer/settings
@onready var btn_upgrades: BaseButton = $PhoneWrapper/Screen/HomeScreen/CenterContainer/GridContainer/upgrades
@onready var btn_tutorial: BaseButton = $PhoneWrapper/Screen/HomeScreen/CenterContainer/GridContainer/tutorial
@onready var btn_decor: BaseButton = $PhoneWrapper/Screen/HomeScreen/CenterContainer/GridContainer/decor

@onready var home_button: BaseButton = $PhoneWrapper/HomeButton

@onready var general_page: Control = $PhoneWrapper/Screen/AppDisplayArea/GeneralPage
@onready var settings_page: Control = $PhoneWrapper/Screen/AppDisplayArea/SettingsPage
@onready var upgrades_page: Control = $PhoneWrapper/Screen/AppDisplayArea/UpgradesPage
@onready var tutorial_page: Control = $PhoneWrapper/Screen/AppDisplayArea/TutorialPage
@onready var decor_page: Control = $PhoneWrapper/Screen/AppDisplayArea/DecorPage

@onready var dot_upgrades: Panel = $PhoneWrapper/Screen/HomeScreen/CenterContainer/GridContainer/upgrades/RedDot
@onready var dot_decor: Panel = $PhoneWrapper/Screen/HomeScreen/CenterContainer/GridContainer/decor/RedDot


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
		open_app(tutorial_page)
	)

	btn_decor.pressed.connect(func():
		open_app(decor_page)
	)

	# =====================================================
	# 手机底部按钮：返回桌面
	# =====================================================
	home_button.pressed.connect(show_home_screen)

	# =====================================================
	# 升级提示：红点 + 震动
	# =====================================================
	_reminder_timer = Timer.new()
	_reminder_timer.wait_time = REMINDER_INTERVAL
	_reminder_timer.one_shot = false
	add_child(_reminder_timer)
	_reminder_timer.timeout.connect(_on_reminder_timeout)

	Gamemanager.kpi_changed.connect(func(_v): _refresh_upgrade_hints())
	Gamemanager.level_changed.connect(func(_v): _refresh_upgrade_hints())

	# 等几帧确保存档加载完成、desk_slots 组就绪后做首次判定
	await get_tree().process_frame
	await get_tree().process_frame
	_trigger_home = trigger_btn.position
	_refresh_upgrade_hints()


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
			# 直接调用你原本收手机的函数
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

	# 玩家点开手机 = 已注意到提示，停止震动
	_stop_shake()

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(phone_wrapper, "position:x", open_x, 0.5)


# =====================================================
# 4. 收回手机
# =====================================================
func close_phone() -> void:
	if _is_locked_by_tutorial:
		return

	if not is_open:
		return

	is_open = false
	
	show_home_screen()
	
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
	tutorial_page.visible = false
	decor_page.visible = false


func lock_for_tutorial() -> void:
	_is_locked_by_tutorial = true
	if not is_open:
		open_phone()


func unlock_from_tutorial() -> void:
	_is_locked_by_tutorial = false
	btn_tutorial.modulate.a = 1.0


# =====================================================
# 8. 升级提示：红点显示 + 震动判定
# =====================================================

# 玩家是否可升级（等级未满 且 KPI 够下一级费用）
func _can_upgrade_player() -> bool:
	var lv: int = Gamemanager.player_level
	if lv >= 5:
		return false
	return Gamemanager.has_enough_kpi(PLAYER_UPGRADE_COST.get(lv, 999999999))

# 是否有任意一组已掌握的桌子可升级
func _can_upgrade_any_desk() -> bool:
	var raw := get_tree().get_nodes_in_group("desk_slots")
	raw.sort_custom(func(a, b): return a.get_index() < b.get_index())
	var unlocked: int = mini(Gamemanager.player_level, raw.size())
	for i in range(unlocked):
		var slot = raw[i]
		var lvl: int = slot.slot_level
		if lvl < 4 and lvl < Gamemanager.max_desk_level and Gamemanager.has_enough_kpi(_desk_cost(lvl)):
			return true
	return false

func _desk_cost(level: int) -> int:
	match level:
		1: return 200
		2: return 500
		3: return 1000
	return 0

# 重新判定可升级状态：更新红点，并在"刚出现"时触发震动
func _refresh_upgrade_hints() -> void:
	if not is_inside_tree():
		return
	var player_up := _can_upgrade_player()
	var desk_up := _can_upgrade_any_desk()

	if is_instance_valid(dot_upgrades):
		dot_upgrades.visible = player_up
	if is_instance_valid(dot_decor):
		dot_decor.visible = desk_up

	var any_up := player_up or desk_up
	if any_up and not _was_upgradable:
		# 从"无"到"有"：抖动 10s 提醒，并开启 15min 周期提醒
		_start_shake(FIRST_SHAKE_DURATION)
		_reminder_timer.start()
	elif not any_up:
		# 没有任何可升级内容：停止一切提醒
		_stop_shake()
		_reminder_timer.stop()
	_was_upgradable = any_up

# 周期提醒：每 15min，若仍有可升级内容且手机关着，抖 5s
func _on_reminder_timeout() -> void:
	if _was_upgradable and not is_open:
		_start_shake(REMINDER_SHAKE_DURATION)


# =====================================================
# 9. 震动动画（只抖 Trigger 触发器）
# =====================================================
func _start_shake(duration: float) -> void:
	# 手机打开时 Trigger 是隐藏的，抖了也看不见，跳过
	if is_open:
		return
	_shake_time_left = max(_shake_time_left, duration)

func _stop_shake() -> void:
	_shake_time_left = 0.0
	if is_instance_valid(trigger_btn):
		trigger_btn.position = _trigger_home

func _process(delta: float) -> void:
	if _shake_time_left <= 0.0:
		return
	if not is_instance_valid(trigger_btn):
		return

	# 手机中途被打开：立即停止
	if is_open:
		_stop_shake()
		return

	_shake_time_left -= delta
	if _shake_time_left <= 0.0:
		trigger_btn.position = _trigger_home
	else:
		var t := Time.get_ticks_msec() / 1000.0
		var off_x := sin(t * SHAKE_FREQ) * SHAKE_AMP
		var off_y := sin(t * SHAKE_FREQ * 1.3) * SHAKE_AMP * 0.5
		trigger_btn.position = _trigger_home + Vector2(off_x, off_y)
