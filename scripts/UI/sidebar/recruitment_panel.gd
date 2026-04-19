# recruitment_panel.gd
extends Control

# ================= UI 节点获取 =================
@onready var normal_empty_lbl = $VBoxContainer/NormalPanel/MarginContainer/LblEmpty
@onready var normal_viewer = $VBoxContainer/NormalPanel/MarginContainer/NormalViewer

@onready var headhunt_locked_lbl = $VBoxContainer/HeadhuntPanel/MarginContainer/LblLocked
@onready var headhunt_box_idle = $VBoxContainer/HeadhuntPanel/MarginContainer/BoxIdle
@onready var headhunt_box_recruiting = $VBoxContainer/HeadhuntPanel/MarginContainer/BoxRecruiting
@onready var headhunt_viewer = $VBoxContainer/HeadhuntPanel/MarginContainer/HeadViewer
@onready var countdown_label = $VBoxContainer/HeadhuntPanel/MarginContainer/BoxRecruiting/LblCountdown

var last_headhunt_state: int = -1
var last_office_status: bool = false

func _ready():
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
	
	# 初始刷一遍 UI
	_on_new_resumes_arrived()
	_update_headhunt_ui()

# ================= 倒计时专属 (唯一需要 _process 的地方) =================
func _process(_delta):
	# 只有在猎头寻访中，才去更新文字，超级省性能
	if RecruitmentManager.current_state == RecruitmentManager.State.RECRUITING:
		countdown_label.text = "寻访中... %.1f" % RecruitmentManager.headhunt_time_left

# ================= 核心：数据下发与同步 =================
func _on_new_resumes_arrived():
	# 普通招聘：如果有数据，且 Viewer 当前是空的，就塞一份【复印件】进去
	if RecruitmentManager.normal_pool.size() > 0 and normal_viewer.current_resumes.is_empty():
		normal_viewer.load_resumes(RecruitmentManager.normal_pool.duplicate()) # 这里的 duplicate 治好了吃简历 Bug
	_update_normal_ui()
	
	# 猎头招聘：如果状态是 READY 且 Viewer 是空的，塞一份【复印件】进去
	if RecruitmentManager.current_state == RecruitmentManager.State.READY and headhunt_viewer.current_resumes.is_empty():
		if RecruitmentManager.headhunt_pool.size() > 0:
			headhunt_viewer.load_resumes(RecruitmentManager.headhunt_pool.duplicate()) # 同上
	_update_headhunt_ui()

# ================= 雇佣与拒绝逻辑 =================
func _hire_from_pool(emp: Employee, pool: Array, viewer: ResumeViewer):
	var cost = (emp.efficiency + emp.quality + emp.experience) * 10
	if Gamemanager.spend_kpi(cost):
		EmployeeManager.hire_employee(emp)
		
		# 1. 划掉原件里的人
		pool.erase(emp) 
		
		# 2. 告诉 Viewer：雇佣成功，你可以把复印件里的人删了并翻页了
		viewer.remove_current_success() 

# 对应 Viewer 的 _on_reject_pressed 信号
func _reject_from_pool(emp: Employee, pool: Array):
	# Viewer 内部已经把复印件删了，我们只需要在这里悄悄把原件也删了即可
	pool.erase(emp)
	print("已拒绝员工，并从全局池中移除: ", emp.employee_name)

# ================= UI 显示更新控制 =================
func _update_normal_ui():
	if normal_viewer.current_resumes.is_empty():
		normal_empty_lbl.show()
		normal_viewer.hide()
	else:
		normal_empty_lbl.hide()
		normal_viewer.show()

func _update_headhunt_ui():
	var current_state = RecruitmentManager.current_state
	var current_office_exists = OfficeManager.has_recruitment_office
	
	if current_state == last_headhunt_state and current_office_exists == last_office_status:
		return
	
	last_headhunt_state = current_state
	last_office_status = current_office_exists
	
	headhunt_locked_lbl.hide()
	headhunt_box_idle.hide()
	headhunt_box_recruiting.hide()
	headhunt_viewer.hide()
	
	if not OfficeManager.has_recruitment_office:
		headhunt_locked_lbl.show()
		return
		
	match RecruitmentManager.current_state:
		RecruitmentManager.State.IDLE:
			headhunt_box_idle.show()
		RecruitmentManager.State.RECRUITING:
			headhunt_box_recruiting.show()
		RecruitmentManager.State.READY:
			headhunt_viewer.show()

# ================= 按键操作 =================
func _on_office_status_updated(_is_active: bool):
	_update_headhunt_ui()

func _execute_headhunt(amount: int):
	var cost = 100 * amount
	if Gamemanager.spend_dollar(cost):
		var duration = 1.0 if amount == 1 else 10.0
		RecruitmentManager.start_headhunt(amount, duration)
		_update_headhunt_ui() # 点击后立刻刷一下 UI 显示倒计时
	else:
		print("老板，Dollar 不够！")

func _on_hire_1_pressed(): _execute_headhunt(1)
func _on_hire_10_pressed(): _execute_headhunt(10)

func _on_all_coworkers_pressed() -> void:
	var warehouse = get_tree().get_first_node_in_group("employee_warehouse")
	if warehouse:
		warehouse.show()
