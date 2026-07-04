#mobilesidebar.gd
extends Control

# =====================================================
# 1. Sidebar 展开 / 收回相关节点
# =====================================================
@onready var phone_wrapper: Control = $PhoneWrapper
@onready var trigger_btn: BaseButton = $Trigger
# 摇晃动画对象：sidebar_trigger 场景里的手机图标（不再摇整个 Trigger 按钮）
@onready var phone_icon: Control = $Trigger/Control/PhoneIcon
# 按钮底板（抖动时变暖黄）、右上角红点
@onready var trigger_bg: Panel = $Trigger/Control/ButtonBg
@onready var trigger_red_dot: Control = $Trigger/Control/RedDot
#@onready var trigger_btn_bcg = $Trigger/TextureRect

# 按钮底色：默认浅灰，抖动提示时变明亮暖黄
const BG_GRAY := Color(0.8, 0.79, 0.75, 1.0)
const BG_YELLOW := Color(1.0, 0.82, 0.25, 1.0)
var _bg_style: StyleBoxFlat   # ButtonBg 的 StyleBoxFlat（运行时改 bg_color）

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
const PLAYER_UPGRADE_COST := {1: 50, 2: 5000, 3: 30000, 4: 100000}

const TILT_FREQ := 2.5            # 倾斜频率（Hz，每秒来回次数）
const TILT_ANGLE := 15.0          # 最大倾斜角度（度）
const FIRST_SHAKE_DURATION := 10.0   # 刚出现可升级时动画持续时间
const REMINDER_SHAKE_DURATION := 5.0 # 周期提醒每次动画时间
const REMINDER_INTERVAL := 900.0     # 周期提醒间隔（15 分钟）

var _was_upgradable := false      # 上一次判定是否有可升级内容
var _shake_time_left := 0.0       # 剩余抖动时间
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
@onready var btn_personal: BaseButton = $PhoneWrapper/Screen/HomeScreen/CenterContainer/GridContainer/Personal

@onready var home_button: BaseButton = $PhoneWrapper/HomeButton
@onready var home_button_2: BaseButton = $PhoneWrapper/HomeButton2
# 盖在 HomeButton2 上的遮挡层：主页显示它挡住按钮，子页面隐藏它露出按钮

@onready var general_page: Control = $PhoneWrapper/Screen/AppDisplayArea/GeneralPage
@onready var settings_page: Control = $PhoneWrapper/Screen/AppDisplayArea/SettingsPage
@onready var upgrades_page: Control = $PhoneWrapper/Screen/AppDisplayArea/UpgradesPage
@onready var tutorial_page: Control = $PhoneWrapper/Screen/AppDisplayArea/TutorialPage
@onready var decor_page: Control = $PhoneWrapper/Screen/AppDisplayArea/DecorPage
@onready var personal_page: Control = $PhoneWrapper/Screen/AppDisplayArea/PersonalPage

@onready var dot_upgrades: Panel = $PhoneWrapper/Screen/HomeScreen/CenterContainer/GridContainer/upgrades/RedDot
@onready var dot_decor: Panel = $PhoneWrapper/Screen/HomeScreen/CenterContainer/GridContainer/decor/RedDot
@onready var time_label: Label = $PhoneWrapper/Screen/Time

# =====================================================
# 手机电量（纯氛围：慢慢掉电，<50% 出现充电器，拖到手机上充电，充满自动停）
# =====================================================
@onready var battery_fill: ColorRect = $PhoneWrapper/Screen/BatteryContainer/BatteryFill
@onready var battery_label: Label = $PhoneWrapper/Screen/BatteryContainer/battery
@onready var charger: TextureRect = $Charger
@onready var phone_base: TextureRect = $PhoneWrapper/PhoneBase

const BATTERY_DRAIN_PER_SEC := 100.0 / (30.0 * 60.0)   # 30 分钟掉完一格 → 每秒掉的百分比
const BATTERY_CHARGE_PER_SEC := 100.0 / (10.0 * 60.0)  # 10 分钟充满 → 每秒充的百分比（比掉电快，像手机）
const BATTERY_LOW := 50.0        # <50% 出现充电器、填充条变黄
const BATTERY_CRITICAL := 20.0   # <20% 填充条变红

# 填充条颜色优先级：充电中(绿) > <20(红) > <50(黄) > 否则(白)
const BAT_COLOR_NORMAL := Color(1, 1, 1, 0.8)
const BAT_COLOR_LOW := Color(0.95, 0.75, 0.15, 1)
const BAT_COLOR_CRITICAL := Color(0.9, 0.2, 0.2, 1)
const BAT_COLOR_CHARGING := Color(0.369, 0.82, 0.5945, 1)

var battery: float = 90.0        # 当前电量 0~100
var is_charging: bool = false
var _last_pct: int = -1           # 上次显示的整数百分比（变化才刷新视觉，省开销）
var _last_charging: bool = false
var _charger_home_pos: Vector2 = Vector2.ZERO
var _charger_dragging: bool = false
var _charger_grab_offset: Vector2 = Vector2.ZERO
var _charger_auto_animating: bool = false   # 0% 自动插电动画进行中，期间不干预充电器显隐
const CHARGER_SHOW_DELAY := 0.3             # 充电器出现的延迟：等手机弹出动画停稳后再冒出来（隐藏不延迟）
var _charger_show_delay_left := CHARGER_SHOW_DELAY


func _ready() -> void:
	# =====================================================
	# 初始状态：手机收回
	# =====================================================
	phone_wrapper.position.x = closed_x
	trigger_btn.show()
	is_open = false
	#trigger_btn_bcg.top_level = true

	# 取 ButtonBg 的样式副本，之后运行时改它的底色（脉冲暖黄/恢复浅灰）
	if is_instance_valid(trigger_bg):
		var sb := trigger_bg.get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			_bg_style = sb.duplicate()
			trigger_bg.add_theme_stylebox_override("panel", _bg_style)
			_bg_style.bg_color = BG_GRAY

	# 初始状态：显示手机桌面
	show_home_screen()

	# 应用菜单图标文字的中英翻译
	_apply_menu_translations()

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
	
	btn_personal.pressed.connect(func():
		open_app(personal_page)
	)

	# =====================================================
	# 手机底部按钮：返回桌面
	# =====================================================
	home_button.pressed.connect(show_home_screen)
	home_button_2.pressed.connect(show_home_screen)

	# =====================================================
	# 升级提示：红点 + 震动
	# =====================================================
	_reminder_timer = Timer.new()
	_reminder_timer.wait_time = REMINDER_INTERVAL
	_reminder_timer.one_shot = false
	add_child(_reminder_timer)
	_reminder_timer.timeout.connect(_on_reminder_timeout)

	# 实时时钟：启动时立即显示，之后每秒刷新
	_update_clock()
	var clock_timer := Timer.new()
	clock_timer.wait_time = 1.0
	clock_timer.autostart = true
	clock_timer.timeout.connect(_update_clock)
	add_child(clock_timer)

	Gamemanager.kpi_changed.connect(func(_v): _refresh_upgrade_hints())
	Gamemanager.level_changed.connect(func(_v): _refresh_upgrade_hints())

	# 电量 / 充电器初始化：拖拽由 _input 自己做命中判定，充电器不参与 GUI
	if is_instance_valid(charger):
		charger.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_charger_home_pos = charger.position
		charger.visible = false
	# 填充条以左边缘为轴缩放（保证从左往右填、右侧透明）
	if is_instance_valid(battery_fill):
		battery_fill.pivot_offset = Vector2.ZERO

	# 等几帧确保存档加载完成、desk_slots 组就绪后做首次判定
	await get_tree().process_frame
	await get_tree().process_frame
	# 布局稳定后设置旋转轴为手机图标中心点
	phone_icon.pivot_offset = phone_icon.size / 2.0

	# 存档此时已加载完（main 的 load_game 在上面这两帧内已跑完），取回电量并刷新显示
	battery = clampf(Gamemanager.phone_battery, 0.0, 100.0)
	_update_battery_visual()
	_update_charger_visibility(0.0)

	_refresh_upgrade_hints()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_apply_menu_translations()

# 中文比英文大几号（解决手机界面中文菜单字太小），按需调这个数
const ZH_MENU_FONT_BONUS := 4
var _base_menu_font_sizes := {}   # 各菜单标签的原始（英文）字号，首次覆盖前记下

func _menu_labels() -> Array:
	return [
		btn_upgrades.get_node("upgrades"),
		btn_tutorial.get_node("Tutorial"),
		btn_general.get_node("GENERAL"),
		btn_settings.get_node("SETTINGS"),
		btn_decor.get_node("DECOR"),
		btn_personal.get_node("PERSONAL"),
	]

# 只在中文时把这几个菜单文字调大；英文保持原始设计字号
func _apply_locale_font_sizes() -> void:
	var is_zh := TranslationServer.get_locale().begins_with("zh")
	for lbl in _menu_labels():
		if not _base_menu_font_sizes.has(lbl):
			_base_menu_font_sizes[lbl] = lbl.get_theme_font_size("font_size")  # 须在覆盖前记下原始字号
		var base: int = _base_menu_font_sizes[lbl]
		var sz: int = (base + ZH_MENU_FONT_BONUS) if is_zh else base
		lbl.add_theme_font_size_override("font_size", sz)

func _apply_menu_translations() -> void:
	btn_upgrades.get_node("upgrades").text = tr("Sidebar_menu_upgrades")
	btn_tutorial.get_node("Tutorial").text = tr("Sidebar_menu_tutorial")
	btn_general.get_node("GENERAL").text = tr("Sidebar_menu_general")
	btn_settings.get_node("SETTINGS").text = tr("Sidebar_menu_settings")
	btn_decor.get_node("DECOR").text = tr("Sidebar_menu_decor")
	btn_personal.get_node("PERSONAL").text = tr("Sidebar_personal_title")
	_apply_locale_font_sizes()


func _input(event: InputEvent) -> void:
	# 1. 如果手机本来就是关着的，雷达不工作
	if not is_open:
		return

	# 0. 充电器拖拽中：优先处理，跟随鼠标移动 / 松手判定，期间不做关机
	if _charger_dragging:
		if event is InputEventMouseMotion:
			charger.global_position = get_global_mouse_position() - _charger_grab_offset
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_charger_dragging = false
			get_viewport().set_input_as_handled()
			_try_plug_in_charger()
		return

	# 2. 捕捉全屏的鼠标左键按下事件
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:

		# 2a. 先看是不是按在充电器上 → 开始拖拽（绝不关机、也不穿透去砸背后的员工）
		if is_instance_valid(charger) and charger.visible \
		and charger.get_global_rect().has_point(get_global_mouse_position()):
			_charger_dragging = true
			_charger_grab_offset = get_global_mouse_position() - charger.global_position
			get_viewport().set_input_as_handled()
			return

		# 3. 拿到手机【真正机身】的物理矩形！
		# 🌟 必须用 PhoneBase（机身贴图），不能用 PhoneWrapper：
		# Screen/按钮/壁纸都比 PhoneWrapper 自身矩形往左上方伸出（左列与顶行 App 图标有一部分在 PhoneWrapper 外），
		# 用 PhoneWrapper 会把这些伸出去的部分误判成“点在手机外”→ 关机并让点击穿透，导致这些按钮有时点不动。
		# PhoneBase 完整包住所有 App 图标和 Home 键，判定才准确。
		var phone_rect = $PhoneWrapper/PhoneBase.get_global_rect()

		# 4. 如果鼠标点的坐标，不在手机机身范围内
		if not phone_rect.has_point(event.global_position):
			# 直接调用你原本收手机的函数
			close_phone()

			# 注意！千万不要写 get_viewport().set_input_as_handled()！
			# 这样点击事件就能像幽灵一样穿透下去，精准砸中外面的按钮！


# =====================================================
# 给世界里的可点击对象（如员工）判断：这个屏幕坐标是否被手机挡住。
# 挡住 = 展开时盖在机身上 / 收起时盖在触发按钮上。
# 这样员工的 _input(它在 GUI 之前、不认 UI 遮挡) 就不会被手机后面的点击穿透触发。
# =====================================================
func blocks_point(global_pos: Vector2) -> bool:
	# 充电器可见时也算遮挡：防止拖它/它盖住时点穿到背后的员工
	if is_instance_valid(charger) and charger.visible and charger.get_global_rect().has_point(global_pos):
		return true
	if is_open:
		return _control_tree_blocks_point(phone_wrapper, global_pos)
	if is_instance_valid(trigger_btn) and trigger_btn.visible:
		return trigger_btn.get_global_rect().has_point(global_pos)
	return false

func _control_tree_blocks_point(control: Control, global_pos: Vector2) -> bool:
	if control == null or not control.is_visible_in_tree():
		return false

	if control.get_global_rect().has_point(global_pos):
		return true

	for child in control.get_children():
		var child_control := child as Control
		if child_control != null and _control_tree_blocks_point(child_control, global_pos):
			return true

	return false


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
	home_button_2.show() 


# =====================================================
# 6. 返回手机桌面
# =====================================================
func show_home_screen() -> void:
	hide_all_pages()
	home_screen.visible = true
	app_display_area.visible = false
	home_button_2.hide()
	  # 主界面：显示遮挡层盖住按钮


# =====================================================
# 7. 隐藏所有 App 页面
# =====================================================
func hide_all_pages() -> void:
	general_page.visible = false
	settings_page.visible = false
	upgrades_page.visible = false
	tutorial_page.visible = false
	decor_page.visible = false
	personal_page.visible = false


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
	for slot in raw:
		# 只看已解锁的桌子组（unlock_at_level <= 当前玩家等级），
		# 不能用场景下标判断解锁——下标顺序与 unlock_at_level 并不一致。
		if slot.unlock_at_level > Gamemanager.player_level:
			continue
		var lvl: int = slot.slot_level
		if lvl < 4 and lvl < Gamemanager.max_desk_level and Gamemanager.has_enough_kpi(_desk_cost(lvl)):
			return true
	return false

func _desk_cost(level: int) -> int:
	match level:
		1: return 1000
		2: return 3000
		3: return 10000
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

	# Trigger 上的「有提醒」指示：红点，仅在有可升级内容时显示
	if is_instance_valid(trigger_red_dot):
		trigger_red_dot.visible = any_up
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
# 9. 倾斜动画（手机图标 PhoneIcon 左右摇摆 ±15°）
# =====================================================
func _start_shake(duration: float) -> void:
	# 手机打开时 Trigger 是隐藏的，跳过
	if is_open:
		return
	_shake_time_left = max(_shake_time_left, duration)

func _stop_shake() -> void:
	_shake_time_left = 0.0
	if is_instance_valid(phone_icon):
		phone_icon.rotation_degrees = 0.0
	_set_trigger_bg(BG_GRAY)

# 设置 Trigger 按钮底色（抖动时调暖黄，结束恢复浅灰）
func _set_trigger_bg(c: Color) -> void:
	if _bg_style != null:
		_bg_style.bg_color = c

func _process(delta: float) -> void:
	_process_battery(delta)   # 电量逻辑每帧都要跑（不能被下面的抖动早退挡住）

	if _shake_time_left <= 0.0:
		return
	if not is_instance_valid(phone_icon):
		return

	# 手机中途被打开：立即停止
	if is_open:
		_stop_shake()
		return

	_shake_time_left -= delta
	if _shake_time_left <= 0.0:
		phone_icon.rotation_degrees = 0.0
		_set_trigger_bg(BG_GRAY)
	else:
		var t := Time.get_ticks_msec() / 1000.0
		phone_icon.rotation_degrees = sin(t * TILT_FREQ * TAU) * TILT_ANGLE
		# 抖动期间底色保持明亮暖黄（不频闪）
		_set_trigger_bg(BG_YELLOW)


func _update_clock() -> void:
	var t := Time.get_time_dict_from_system()
	time_label.text = "%02d:%02d" % [t.hour, t.minute]


# =====================================================
# 10. 手机电量：掉电 / 充电 / 充电器
# =====================================================
func _process_battery(delta: float) -> void:
	if is_charging:
		battery = minf(battery + BATTERY_CHARGE_PER_SEC * delta, 100.0)
		if battery >= 100.0:
			battery = 100.0
			is_charging = false   # 充满自动停充
	else:
		battery = maxf(battery - BATTERY_DRAIN_PER_SEC * delta, 0.0)
		if battery <= 0.0 and not _charger_auto_animating:
			_auto_plug_at_zero()   # 0% 兜底自动充电

	Gamemanager.phone_battery = battery   # 实时同步给存档
	_update_battery_visual()
	_update_charger_visibility(delta)


# 填充条长度按百分比、颜色按状态刷新（整数百分比或充电状态变化才真正改，省开销）
func _update_battery_visual() -> void:
	if not is_instance_valid(battery_fill):
		return
	var pct := int(battery)
	if pct == _last_pct and is_charging == _last_charging:
		return
	_last_pct = pct
	_last_charging = is_charging

	# 左对齐横向缩放：有百分之多少就填多少长度，其余透明（默认 pivot=(0,0)，从左边缩）
	battery_fill.scale.x = clampf(battery / 100.0, 0.0, 1.0)

	var c: Color
	if is_charging:
		c = BAT_COLOR_CHARGING
	elif battery < BATTERY_CRITICAL:
		c = BAT_COLOR_CRITICAL
	elif battery < BATTERY_LOW:
		c = BAT_COLOR_LOW
	else:
		c = BAT_COLOR_NORMAL
	battery_fill.color = c

	if is_instance_valid(battery_label):
		battery_label.text = "%d%%" % pct


# 充电器显隐：手机开着 + 电量 <50% + 没在充电 时出现；拖拽/自动动画期间不干预。
# 出现要延迟 CHARGER_SHOW_DELAY（等手机弹出动画停稳），隐藏则立即。
func _update_charger_visibility(delta: float) -> void:
	if _charger_dragging or _charger_auto_animating:
		return
	if not is_instance_valid(charger):
		return
	var should := is_open and battery < BATTERY_LOW and not is_charging
	if should:
		if charger.visible:
			return
		# 满足条件但还没显示：先倒计时，等手机停稳再冒出来
		_charger_show_delay_left -= delta
		if _charger_show_delay_left <= 0.0:
			charger.visible = true
	else:
		# 不该显示：立即隐藏，并重置延迟（下次出现重新等 0.3s）
		charger.visible = false
		_charger_show_delay_left = CHARGER_SHOW_DELAY


# 松开充电器：落在手机机身上就开始充电，否则弹回原位
func _try_plug_in_charger() -> void:
	if not is_instance_valid(charger):
		return
	var phone_rect = phone_base.get_global_rect()
	if phone_rect.has_point(get_global_mouse_position()):
		_start_charging()
	else:
		charger.position = _charger_home_pos   # 没拖到手机上 → 回原位


# 开始充电：收起充电器、电量转绿、逐渐充满
func _start_charging() -> void:
	is_charging = true
	if is_instance_valid(charger):
		charger.visible = false
		charger.position = _charger_home_pos   # 复位，下次再用
		charger.modulate.a = 1.0
	_update_battery_visual()   # 立刻变绿


# 电量掉到 0% 的兜底（方案 A）：
#   手机开着 → 充电器自动往右下平移 + 淡出，动画完再开始充电；
#   手机关着（trigger 态，看不见）→ 直接开始充电。
func _auto_plug_at_zero() -> void:
	if is_charging or _charger_auto_animating or _charger_dragging:
		return
	if is_open and is_instance_valid(charger):
		_charger_auto_animating = true
		charger.visible = true
		charger.modulate.a = 1.0
		charger.position = _charger_home_pos
		var t := create_tween()
		t.set_parallel(true)
		t.tween_property(charger, "position", _charger_home_pos + Vector2(120, 120), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		t.tween_property(charger, "modulate:a", 0.0, 0.5)
		t.chain().tween_callback(func():
			if is_instance_valid(charger):
				charger.hide()
				charger.position = _charger_home_pos
				charger.modulate.a = 1.0
			_charger_auto_animating = false
			_start_charging()
		)
	else:
		_start_charging()
