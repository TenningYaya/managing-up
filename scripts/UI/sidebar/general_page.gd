extends Control

@onready var hit_label = $"VBoxContainer/total hit"
@onready var time_label = $"VBoxContainer/total time"
@onready var total_emp_label = $"VBoxContainer/number of employee"
@onready var r_emp_label = $"VBoxContainer/R employee"
@onready var sr_emp_label = $"VBoxContainer/SR employee"
@onready var ssr_emp_label = $"VBoxContainer/SSR employee"

func _process(_delta):
	# 如果面板不可见，就不要在后台空跑计算，节省性能
	if not visible:
		return
		
	# 更新总时间和总点击
	hit_label.text = "TOTAL HIT: " + str(Gamemanager.total_hits)
	time_label.text = "TOTAL TIME: " + _format_time(Gamemanager.total_time)
	
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
				
	total_emp_label.text = "NUMBER OF EMPLOYEE: " + str(total_count)
	r_emp_label.text = "R EMPLOYEE: " + str(r_count)
	sr_emp_label.text = "SR EMPLOYEE: " + str(sr_count)
	ssr_emp_label.text = "SSR EMPLOYEE: " + str(ssr_count)

func _format_time(seconds: float) -> String:
	var mins = int(seconds / 60.0)
	var secs = int(seconds) % 60
	# 格式化为 "12m 34s"
	return str(mins) + "m " + str(secs) + "s"
