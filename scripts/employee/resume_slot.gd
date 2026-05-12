#resume_slot.gd

extends HBoxContainer # 或者是你根节点的类型
class_name ResumeSlot

# 🌟 这个组件专属的信号：告诉外界“我被点了，点的是这个员工”
signal hire_requested(emp: Employee)
signal reject_requested(emp: Employee)

@onready var resume_card = $ResumeCard
@onready var hire_btn = $HBoxContainer/HireBtn
@onready var reject_btn = $HBoxContainer/RejectBtn

var current_employee: Employee

func _ready() -> void:
	# 内部按钮连内部函数
	hire_btn.pressed.connect(_on_hire_pressed)
	reject_btn.pressed.connect(_on_reject_pressed)

# 外部调用：给这个坑位塞数据
func setup_slot(emp: Employee) -> void:
	current_employee = emp
	
	if resume_card.has_method("setup"):
		resume_card.setup(emp)
		
	# 坑位自己算钱、自己改按钮文字！主控代码不用管了
	#var total_stats = emp.efficiency + emp.quality + emp.experience
	#var cost_kpi = total_stats * 10
	hire_btn.text = "Yes!"

func _on_hire_pressed() -> void:
	if current_employee:
		hire_requested.emit(current_employee) # 把当前员工扔出去

func _on_reject_pressed() -> void:
	if current_employee:
		reject_requested.emit(current_employee)
