# resume_viewer.gd
extends Control
class_name ResumeViewer

signal on_hire_attempted(employee_data: Employee)
signal on_rejected(employee_data: Employee)
signal on_empty() # 当所有简历都被处理完时发出

@onready var left_arrow = $HBoxContainer/LeftArrow
@onready var right_arrow = $HBoxContainer/RightArrow
@onready var cards_container = $HBoxContainer/CardsContainer # 🌟 新增的容器

var current_resumes: Array[Employee] = []
var current_page: int = 0
const ITEMS_PER_PAGE: int = 3 # 🌟 一页展示几张

func _ready():
	left_arrow.pressed.connect(_on_left_pressed)
	right_arrow.pressed.connect(_on_right_pressed)
	
	for slot in cards_container.get_children():
		if slot is ResumeSlot: # 前提是你在 resume_slot.gd 顶部写了 class_name ResumeSlot
			slot.hire_requested.connect(_on_slot_hire_requested)
			slot.reject_requested.connect(_on_slot_reject_requested)

func _update_display() -> void:
	if current_resumes.is_empty():
		on_empty.emit()
		hide()
		return
		
	show()
	
	# 🌟 新增：过滤出一个纯净的 slots 数组，只装真正的卡片坑位！
	var valid_slots = []
	for child in cards_container.get_children():
		if child is ResumeSlot: # 认准你的真实组件
			valid_slots.append(child)
			
	var start_index = current_page * ITEMS_PER_PAGE
	
	# 🌟 把原来的 slots 换成 valid_slots
	for i in range(valid_slots.size()):
		var slot = valid_slots[i]
		var resume_index = start_index + i
		
		if resume_index < current_resumes.size():
			slot.show()
			var current_emp = current_resumes[resume_index]
			if slot.has_method("setup_slot"):
				slot.setup_slot(current_emp)
		else:
			slot.hide()
			
	_update_arrows()

func _update_arrows() -> void:
	# 左箭头逻辑
	if current_page > 0:
		left_arrow.modulate.a = 1.0
		left_arrow.disabled = false
		left_arrow.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		left_arrow.modulate.a = 0.0
		left_arrow.disabled = true
		left_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
	# 右箭头逻辑：如果 (当前页 + 1) * 3 还没超过总人数，说明还有下一页
	var has_next_page = (current_page + 1) * ITEMS_PER_PAGE < current_resumes.size()
	
	if has_next_page:
		right_arrow.modulate.a = 1.0
		right_arrow.disabled = false
		right_arrow.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		# 🌟 关键：不 hide()，只变透明并无视鼠标
		right_arrow.modulate.a = 0.0
		right_arrow.disabled = true
		right_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _on_left_pressed():
	if current_page > 0:
		current_page -= 1
		_update_display()

func _on_right_pressed():
	if (current_page + 1) * ITEMS_PER_PAGE < current_resumes.size():
		current_page += 1
		_update_display()

# 🌟 新的按钮回调：自带坑位索引
func _on_slot_hire_pressed(slot_index: int):
	var target_index = (current_page * ITEMS_PER_PAGE) + slot_index
	if target_index < current_resumes.size():
		var emp = current_resumes[target_index]
		on_hire_attempted.emit(emp)

func _on_slot_reject_pressed(slot_index: int):
	var target_index = (current_page * ITEMS_PER_PAGE) + slot_index
	if target_index < current_resumes.size():
		var emp = current_resumes[target_index]
		on_rejected.emit(emp)
		# 拒绝后直接从当前列表删除该员工
		remove_employee(emp)

# 外部调用：如果雇佣成功，从列表移除此人
func remove_employee(emp: Employee) -> void:
	current_resumes.erase(emp)
	
	# 防止删完人之后，当前页变成了空页（比如最后一页的最后一个人被招募了）
	var max_page = max(0, ceil(float(current_resumes.size()) / ITEMS_PER_PAGE) - 1)
	if current_page > max_page:
		current_page = max_page
		
	_update_display()
	
func load_resumes(resumes: Array[Employee]) -> void:
	current_resumes = resumes
	current_page = 0
	_update_display()

func _on_slot_hire_requested(emp: Employee):
	on_hire_attempted.emit(emp)

func _on_slot_reject_requested(emp: Employee):
	on_rejected.emit(emp)
	remove_employee(emp)
