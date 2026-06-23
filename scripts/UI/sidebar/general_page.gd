extends Control

@onready var hit_label = $"VBoxContainer/total hit"
@onready var speedup_label = $"VBoxContainer/speedup count"
@onready var time_label = $"VBoxContainer/total time"
@onready var total_emp_label = $"VBoxContainer/number of employee"
@onready var r_emp_label = $"VBoxContainer/R employee"
@onready var sr_emp_label = $"VBoxContainer/SR employee"
@onready var ssr_emp_label = $"VBoxContainer/SSR employee"
@onready var title_label = $general

func _ready():
	title_label.text = tr("Sidebar_general_title")

# 语言切换时重刷标题（统计项在 _process 里每帧用 tr() 重设，可见时会自动跟随）
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		title_label.text = tr("Sidebar_general_title")

func _process(_delta):
	# 如果面板不可见，就不要在后台空跑计算，节省性能
	if not visible:
		return
		
	# 更新总时间和总点击
	hit_label.text = tr("Sidebar_general_total_hit") + ": " + str(Gamemanager.total_hits)
	speedup_label.text = tr("Sidebar_general_texted_coworker") + ": " + str(Gamemanager.total_speedups)
	time_label.text = tr("Sidebar_general_total_time") + ": " + _format_time(Gamemanager.total_time)
	
	var total_count = EmployeeManager.my_employees.size()
	var r_count = 0
	var sr_count = 0
	var ssr_count = 0
	
	for emp in EmployeeManager.my_employees:
		# 使用 Employee 里的 enum 进行精确匹配
		match emp.rarity:
			Employee.Rarity.R:
				r_count += 1
			Employee.Rarity.SR:
				sr_count += 1
			Employee.Rarity.SSR:
				ssr_count += 1
				
	total_emp_label.text = tr("Siderbar_general_#_of_employee") + ": " + str(total_count)
	r_emp_label.text = tr("Siderbar_general_R_employee") + ": " + str(r_count)
	sr_emp_label.text = tr("Siderbar_general_SR_employee") + ": " + str(sr_count)
	ssr_emp_label.text = tr("Siderbar_general_SSR_employee") + ": " + str(ssr_count)

func _format_time(seconds: float) -> String:
	var mins = int(seconds / 60.0)
	var secs = int(seconds) % 60
	# 格式化为 "12m 34s"
	return str(mins) + "m " + str(secs) + "s"
