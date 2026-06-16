# recruitment_panel.gd
extends Control

# ================= UI 节点获取 =================
@onready var normal_viewer = $VBoxContainer/NormalPanel/MarginContainer/NormalViewer
@onready var normal_no_resume = $VBoxContainer/NormalPanel/MarginContainer/NoResumePanel
@onready var lbl_normal_countdown = $VBoxContainer/NormalPanel/MarginContainer/NoResumePanel/NormalCountdown

@onready var headhunt_box_idle = $VBoxContainer/HeadhuntPanel/MarginContainer/BoxIdle
@onready var headhunt_box_recruiting = $VBoxContainer/HeadhuntPanel/MarginContainer/BoxRecruiting
@onready var headhunt_viewer = $VBoxContainer/HeadhuntPanel/MarginContainer/HeadViewer
@onready var countdown_label = $VBoxContainer/HeadhuntPanel/MarginContainer/BoxRecruiting/HeadCountdown
@onready var headhunt_locked = $VBoxContainer/HeadhuntPanel/MarginContainer/HeadhuntLocked
@onready var hire_tip_label: Label = $NotEnoughKPI

var last_normal_count: int = -1
var last_headhunt_state: int = -1
var last_office_status: bool = false

var dragging = false
var drag_offset = Vector2()
var _tip_tween: Tween = null

func _ready():
	#RecruitmentManager.normal_pool.clear()
	#RecruitmentManager.headhunt_pool.clear()
	#RecruitmentManager.new_resumes_arrived.emit()
	
	# 1. 绑定【录用】信号
	normal_viewer.on_hire_attempted.connect(_hire_from_pool.bind(RecruitmentManager.normal_pool, normal_viewer))
	headhunt_viewer.on_hire_attempted.connect(_hire_from_pool.bind(RecruitmentManager.headhunt_pool, headhunt_viewer))
	
	# 2. 绑定【拒绝】信号（关键修复：复印件被删了，原件也得删）
	normal_viewer.on_rejected.connect(_reject_from_pool.bind(RecruitmentManager.normal_pool))
	headhunt_viewer.on_rejected.connect(_reject_from_pool.bind(RecruitmentManager.headhunt_pool))
	
	# 3. 绑定 Viewer 空状态信号
	normal_viewer.on_empty.connect(_update_normal_ui)
	headhunt_viewer.on_empty.connect(func():
		RecruitmentManager.current_state = RecruitmentManager.State.IDLE
		_update_headhunt_ui()
	)
	
	# 4. 监听全局数据更新信号（替代以前的 _process 轮询）
	OfficeManager.recruitment_office_status_changed.connect(_on_office_status_updated)
	RecruitmentManager.new_resumes_arrived.connect(_on_new_resumes_arrived) # 监听新简历到达
	
	var normal_hr = $VBoxContainer/NormalPanel/MarginContainer/NoResumePanel/HRButton
	var head_hr = $VBoxContainer/HeadhuntPanel/MarginContainer/BoxRecruiting/HRButton
	normal_hr.viewer_ready.connect(_show_normal_viewer)
	head_hr.viewer_ready.connect(_show_headhunt_viewer)

	# 初始刷一遍 UI
	_on_new_resumes_arrived()
	_update_headhunt_ui()

# ================= 倒计时专属 (唯一需要 _process 的地方) =================
func _process(_delta):
	# 只有在猎头寻访中，才去更新文字，超级省性能
	if RecruitmentManager.current_state == RecruitmentManager.State.RECRUITING:
		countdown_label.text = _format_countdown(RecruitmentManager.headhunt_time_left)

	# 普通招募：等待面板可见时，刷新“下一个免费简历”的倒计时
	if lbl_normal_countdown.visible:
		lbl_normal_countdown.text = _format_countdown(RecruitmentManager.free_recruit_time_left)

# ================= 核心：数据下发与同步 =================
func _on_new_resumes_arrived():
	var normal_hr = $VBoxContainer/NormalPanel/MarginContainer/NoResumePanel/HRButton
	if RecruitmentManager.normal_pool.size() > 0:
		normal_viewer.load_resumes(RecruitmentManager.normal_pool.duplicate())
		# load_resumes 内部会调 show()，如果动画还没放完要立刻压回去
		if normal_hr and normal_hr.is_in_end_sequence:
			normal_viewer.hide()
	_update_normal_ui()

	# --- 猎头招聘的补货逻辑 ---
	if RecruitmentManager.current_state == RecruitmentManager.State.READY:
		if RecruitmentManager.headhunt_pool.size() > 0:
			headhunt_viewer.load_resumes(RecruitmentManager.headhunt_pool.duplicate())
			var head_hr = $VBoxContainer/HeadhuntPanel/MarginContainer/BoxRecruiting/HRButton
			if head_hr and head_hr.is_in_end_sequence:
				headhunt_viewer.hide()
	_update_headhunt_ui()

func _hire_from_pool(emp: Employee, pool: Array, viewer: ResumeViewer):
	# 1. 计算所需 KPI
	var cost = RecruitmentManager.calculate_hire_cost(emp)
	
	# 2. 检查并扣钱
	if Gamemanager.spend_kpi(cost):
		
		# 只发这一个信号，剩下的交给 DropArea 处理。
		Gamemanager.request_employee_drop.emit(emp)
		
		# 3. 把这张“简历复印件”从当前的 Viewer 列表里移除并翻页
		viewer.remove_employee(emp)
		
		# 4. 把这个“员工原件”从全局简历池里彻底划掉
		pool.erase(emp)
		RecruitmentManager.new_resumes_arrived.emit()
		# 5. 强制触发一次数量检测，确保 UI 状态更新
		if pool == RecruitmentManager.normal_pool:
			last_normal_count = pool.size()
			_update_normal_ui()
			
	else:
		# 钱不够时的处理
		print("【招聘中心】KPI 不足！需要: ", cost, " 当前仅有: ", Gamemanager.kpi)
		show_floating_tip("INGAME_TIP_NOT_ENOUGH_HIRE_COUNT")
		
# 对应 Viewer 的 _on_reject_pressed 信号
func _reject_from_pool(emp: Employee, pool: Array):
	# Viewer 内部已经把复印件删了，我们只需要在这里悄悄把原件也删了即可
	pool.erase(emp)
	RecruitmentManager.new_resumes_arrived.emit()
# ================= UI 显示更新控制 =================
func _update_normal_ui():
	var hr = $VBoxContainer/NormalPanel/MarginContainer/NoResumePanel/HRButton
	if hr and hr.is_in_end_sequence:
		return  # 等动画播完再说
	if normal_viewer.current_resumes.is_empty():
		normal_no_resume.show()
		normal_viewer.hide()
		# 教程完成后，在等待面板上显示距离下一个免费招募出现的倒计时
		lbl_normal_countdown.visible = Gamemanager.is_tutorial_completed
	else:
		normal_no_resume.hide()
		normal_viewer.show()
		lbl_normal_countdown.visible = false

# 把剩余秒数格式化成 MM:SS
func _format_countdown(seconds: float) -> String:
	var total = int(ceil(max(seconds, 0.0)))
	return "%02d:%02d" % [total / 60, total % 60]

func _update_headhunt_ui():
	var current_state = RecruitmentManager.current_state
	var current_office_exists = OfficeManager.has_recruitment_office
	
	if current_state == last_headhunt_state and current_office_exists == last_office_status:
		return
	
	last_headhunt_state = current_state
	last_office_status = current_office_exists
	
	headhunt_locked.hide()
	headhunt_box_idle.hide()
	headhunt_box_recruiting.hide()
	headhunt_viewer.hide()
	
	if not OfficeManager.has_recruitment_office:
		headhunt_locked.show()
		return
		
	match RecruitmentManager.current_state:
		RecruitmentManager.State.IDLE:
			headhunt_box_idle.show()
		RecruitmentManager.State.RECRUITING:
			headhunt_box_recruiting.show()
		RecruitmentManager.State.READY:
			var hr = $VBoxContainer/HeadhuntPanel/MarginContainer/BoxRecruiting/HRButton
			if hr and hr.is_in_end_sequence:
				headhunt_box_recruiting.show()
			else:
				headhunt_viewer.show()

# ================= 按键操作 =================
func _on_office_status_updated(_is_active: bool):
	_update_headhunt_ui()

func _execute_headhunt(amount: int):
	var cost = 100 * amount
	if Gamemanager.spend_dollar(cost):
		var duration = 30.0 if amount == 1 else 270.0
		RecruitmentManager.start_headhunt(amount, duration)
		_update_headhunt_ui() # 点击后立刻刷一下 UI 显示倒计时
	else:
		show_floating_tip("INGAME_TIP_NOT_ENOUGH_DOLLAR")

func show_floating_tip(text_key: String) -> void:
	# 🌟【核心修复】：如果上一个动画还在跑，立刻杀掉它！
	if _tip_tween and _tip_tween.is_valid():
		_tip_tween.kill()
		
	# 1. 设置文字
	hire_tip_label.text = tr(text_key)
	
	# 🌟【关键修改】：根据语言动态设置字号
	# 只需要给 Label 的 LabelSettings 赋值，Godot 会自动处理更新
	var settings = LabelSettings.new()
	settings.font_color = Color.RED
	if TranslationServer.get_locale().begins_with("zh"):
		settings.font_size = 14  # 中文设小一点
	else:
		settings.font_size = 16  # 英文保持默认大小
	
	hire_tip_label.label_settings = settings
	
	# 2. 强行提到最前面，并恢复完全不透明
	hire_tip_label.show()
	hire_tip_label.z_index = 100 
	hire_tip_label.modulate.a = 1.0 # 🌟 确保每次点都先恢复 100% 可见
	
	# 3. 创建新的专属动画，并把它存到变量里
	_tip_tween = create_tween()
	
	# 4. 动画序列：停留 1 秒 -> 0.5 秒渐隐 -> 隐藏节点
	_tip_tween.tween_interval(1.0)       
	_tip_tween.tween_property(hire_tip_label, "modulate:a", 0.0, 0.5) 
	_tip_tween.tween_callback(func(): hire_tip_label.hide())
	
func _on_hire_1_pressed(): _execute_headhunt(1)
func _on_hire_10_pressed(): _execute_headhunt(10)

func _on_title_bar_gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			drag_offset = get_global_mouse_position() - global_position
			
	if event is InputEventMouseMotion and dragging:
		global_position = get_global_mouse_position() - drag_offset


func _on_close_panel_pressed() -> void:
	self.hide()
	
func _show_normal_viewer() -> void:
	normal_no_resume.hide()
	normal_viewer.show()

func _show_headhunt_viewer() -> void:
	headhunt_box_recruiting.hide()
	headhunt_viewer.show()
