# recruitment_panel.gd
extends Control

# ================= UI 节点获取 =================
# --- 普通招聘区 ---
@onready var normal_empty_lbl = $VBoxContainer/NormalPanel/MarginContainer/LblEmpty # “当前无简历投递”字样
@onready var normal_viewer = $VBoxContainer/NormalPanel/MarginContainer/NormalViewer

# --- 猎头招聘区 ---
@onready var headhunt_locked_lbl = $VBoxContainer/HeadhuntPanel/MarginContainer/LblLocked # “开设猎头办公室后解锁”
@onready var headhunt_box_idle = $VBoxContainer/HeadhuntPanel/MarginContainer/BoxIdle # 里面有招1次、招10次按钮
@onready var headhunt_box_recruiting = $VBoxContainer/HeadhuntPanel/MarginContainer/BoxRecruiting # 里面有倒计时
@onready var headhunt_viewer = $VBoxContainer/HeadhuntPanel/MarginContainer/HeadViewer # 猎头的简历名片组件
@onready var countdown_label = $VBoxContainer/HeadhuntPanel/MarginContainer/BoxRecruiting/LblCountdown
@onready var headhunt_btn_1 = $VBoxContainer/HeadhuntPanel/MarginContainer/BoxIdle/BtnHire1
@onready var headhunt_btn_10 = $VBoxContainer/HeadhuntPanel/MarginContainer/BoxIdle/BtnHire10

# 用于记录上一次的简历数量，防止每帧都在重新加载导致无法翻页
var last_normal_count: int = -1

# 假设这里有一个判断是否解锁了猎头办公室的变量，你以后可以接入 Gamemanager
var is_headhunt_unlocked: bool = true 
var last_headhunt_state: int = -1 # 记录上一次的状态
var last_office_status: bool = false # 记录办公室是否解锁的状态

func _ready():
	# 监听 Viewer 的雇佣信号
	normal_viewer.on_hire_attempted.connect(_hire_from_pool.bind(RecruitmentManager.normal_pool, normal_viewer))
	headhunt_viewer.on_hire_attempted.connect(_hire_from_pool.bind(RecruitmentManager.headhunt_pool, headhunt_viewer))
	
	# --- 【关键补全】连接猎头招聘按钮 ---
	# 只要点下按钮，就去问大脑要人
	
	# 监听 Viewer 翻空了的信号，这样全拒绝后能切回空状态
	normal_viewer.on_empty.connect(_update_normal_ui)
	headhunt_viewer.on_empty.connect(func():
		RecruitmentManager.current_state = RecruitmentManager.State.IDLE
		_update_headhunt_ui()
	)
	# 1. 监听单例的信号：当办公室状态变了，我立刻刷新
	OfficeManager.recruitment_office_status_changed.connect(_on_office_status_updated)
	
	# 强行初始化一次界面状态
	_update_normal_ui()
	_update_headhunt_ui()
	
func _process(_delta):
	# --- 1. 普通招聘视图状态机 ---
	# 如果池子里的数量发生变化（来了新简历，或者招了人）
	var current_normal_count = RecruitmentManager.normal_pool.size()
	if current_normal_count != last_normal_count:
		last_normal_count = current_normal_count
		if current_normal_count > 0:
			# 传数据给名片组件
			normal_viewer.load_resumes(RecruitmentManager.normal_pool)
		_update_normal_ui()
	
	# --- 2. 猎头招聘视图状态机 ---
	_update_headhunt_ui()
	if RecruitmentManager.current_state == RecruitmentManager.State.RECRUITING:
		countdown_label.text = "寻访中... %.1f" % RecruitmentManager.headhunt_time_left

# ================= 状态机：普通招聘显示切换 =================
func _update_normal_ui():
	# 如果没有简历
	if RecruitmentManager.normal_pool.is_empty():
		normal_empty_lbl.show()
		normal_viewer.hide()
	else:
		# 如果有简历
		normal_empty_lbl.hide()
		normal_viewer.show()

# ================= 状态机：猎头招聘显示切换 =================
func _update_headhunt_ui():
	
	var current_state = RecruitmentManager.current_state
	var current_office_exists = OfficeManager.has_recruitment_office
	
	# 【核心修复】：如果状态没变，直接 return，不要去操作 show/hide！
	if current_state == last_headhunt_state and current_office_exists == last_office_status:
		return
	
	# 只有变了才往下走，并更新记录
	last_headhunt_state = current_state
	last_office_status = current_office_exists
	
	print("检测到状态变化，刷新猎头 UI 布局")
	
	# 先把所有东西都隐藏，防止叠在一起！
	headhunt_locked_lbl.hide()
	headhunt_box_idle.hide()
	headhunt_box_recruiting.hide()
	headhunt_viewer.hide()
	
	# 1. 没解锁状态
	if not OfficeManager.has_recruitment_office:
		headhunt_locked_lbl.show()
		return
		
	# 2. 解锁了，根据 Manager 的状态显示唯一对应的内容
	match RecruitmentManager.current_state:
		RecruitmentManager.State.IDLE:
			headhunt_box_idle.show() # 显示：招1次/招10次按钮
			
		RecruitmentManager.State.RECRUITING:
			headhunt_box_recruiting.show() # 显示：倒计时
			countdown_label.text = "寻访中... 等待时间 %.1f" % RecruitmentManager.headhunt_time_left
			
		RecruitmentManager.State.READY:
			headhunt_viewer.show() # 显示：简历名片
			# 如果组件当前没加载数据，加载一下
			if headhunt_viewer.current_resumes.is_empty() and RecruitmentManager.headhunt_pool.size() > 0:
				headhunt_viewer.load_resumes(RecruitmentManager.headhunt_pool)

# ================= 雇佣逻辑 =================
func _hire_from_pool(emp: Employee, pool: Array, viewer: ResumeViewer):
	var cost = (emp.efficiency + emp.quality + emp.experience) * 10
	if Gamemanager.spend_kpi(cost):
		EmployeeManager.hire_employee(emp)
		pool.erase(emp) # 从池子里删掉
		viewer.remove_current_success() # 让 UI 翻到下一页
		
		# 强制更新数量，触发 UI 刷新
		if pool == RecruitmentManager.normal_pool:
			last_normal_count = pool.size()
			_update_normal_ui()

func _on_office_status_updated(_is_active: bool):
	_update_headhunt_ui()

# 核心逻辑提取出来
func _execute_headhunt(amount: int):
	var cost = 100 * amount
	if Gamemanager.spend_dollar(cost):
		var duration = 1.0 if amount == 1 else 10.0
		RecruitmentManager.start_headhunt(amount, duration)
	else:
		print("老板，Dollar 不够！")

# 对应招 1 次的按钮
func _on_hire_1_pressed():
	print("【手动实锤】招 1 次按钮按下")
	_execute_headhunt(1)

# 对应招 10 次的按钮
func _on_hire_10_pressed():
	print("【手动实锤】招 10 次按钮按下")
	_execute_headhunt(10)
