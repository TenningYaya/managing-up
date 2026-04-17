# resume_viewer.gd
extends Control
class_name ResumeViewer

signal on_hire_attempted(employee_data: Employee)
signal on_rejected(employee_data: Employee)
signal on_empty() # 当所有简历都被处理完时发出

@onready var left_arrow = $HBoxContainer/LeftArrow
@onready var right_arrow = $HBoxContainer/RightArrow
@onready var resume_card = $HBoxContainer/VBoxContainer/ResumeCard
@onready var hire_btn = $HBoxContainer/VBoxContainer/HBoxContainer/HireBtn
@onready var reject_btn = $HBoxContainer/VBoxContainer/HBoxContainer/RejectBtn

var current_resumes: Array[Employee] = []
var current_index: int = 0

func _ready():
	left_arrow.pressed.connect(_on_left_pressed)
	right_arrow.pressed.connect(_on_right_pressed)
	hire_btn.pressed.connect(_on_hire_pressed)
	reject_btn.pressed.connect(_on_reject_pressed)

# 外部调用：把简历塞进这个组件
func load_resumes(resumes: Array[Employee]) -> void:
	current_resumes = resumes
	current_index = 0
	_update_display()

func _update_display() -> void:
	if current_resumes.is_empty():
		on_empty.emit()
		hide()
		return
		
	show()
	var current_emp = current_resumes[current_index]
	
	# 假设你的卡片 prefab 有一个 setup 方法来显示数据
	if resume_card.has_method("setup"):
		resume_card.setup(current_emp)
	
	# 如果你的属性名字不一样，请在这里修改
	var total_stats = current_emp.efficiency + current_emp.quality + current_emp.experience
	var cost_kpi = total_stats * 10
	hire_btn.text = "花 %d KPI 雇佣" % cost_kpi
	
	# 更新箭头显示状态
	left_arrow.visible = (current_index > 0)
	right_arrow.visible = (current_index < current_resumes.size() - 1)

func _on_left_pressed():
	if current_index > 0:
		current_index -= 1
		_update_display()

func _on_right_pressed():
	if current_index < current_resumes.size() - 1:
		current_index += 1
		_update_display()

func _on_hire_pressed():
	# 把当前这个人发给主系统去扣钱入职
	on_hire_attempted.emit(current_resumes[current_index])

func _on_reject_pressed():
	# 抬走下一个，直接删除并更新
	var rejected_emp = current_resumes.pop_at(current_index)
	on_rejected.emit(rejected_emp)
	# 防止越界
	if current_index >= current_resumes.size() and current_index > 0:
		current_index -= 1
	_update_display()

# 外部调用：如果雇佣成功，从列表移除此人
func remove_current_success():
	current_resumes.pop_at(current_index)
	if current_index >= current_resumes.size() and current_index > 0:
		current_index -= 1
	_update_display()
