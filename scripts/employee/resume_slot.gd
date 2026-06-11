#resume_slot.gd

extends Panel # 或者是你根节点的类型
class_name ResumeSlot

# 🌟 这个组件专属的信号：告诉外界“我被点了，点的是这个员工”
signal hire_requested(emp: Employee)
signal reject_requested(emp: Employee)

@onready var resume_card = $CardContainer/ResumeCard
@onready var hire_btn = $CardContainer/SelectionContainer/HireBtn
@onready var reject_btn = $CardContainer/SelectionContainer/RejectBtn
@onready var bg_texture_rect = $TextureRect # 你的背景节点


var current_employee: Employee

# 🌟 在编辑器里把两张背景图拖进去
@export var normal_bg: Texture2D
@export var headhunt_bg: Texture2D

func _ready() -> void:
	# 内部按钮连内部函数
	hire_btn.pressed.connect(_on_hire_pressed)
	reject_btn.pressed.connect(_on_reject_pressed)

# 外部调用：给这个坑位塞数据
func setup_slot(emp: Employee) -> void:
	current_employee = emp
	
		
	if emp.is_headhunt:
		bg_texture_rect.texture = headhunt_bg
	else:
		bg_texture_rect.texture = normal_bg
	
	if resume_card.has_method("setup"):
		resume_card.setup(emp)
	
	reject_btn.add_to_group("reject_buttons")
	
	# 看大总管脸色行事
	if Gamemanager.is_reject_button_disabled:
		reject_btn.disabled = true # 💥 进场直接变灰禁用！

func _on_hire_pressed() -> void:
	if current_employee:
		hire_requested.emit(current_employee) # 把当前员工扔出去

func _on_reject_pressed() -> void:
	if current_employee:
		reject_requested.emit(current_employee)
