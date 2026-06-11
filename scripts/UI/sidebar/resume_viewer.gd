# resume_viewer.gd
extends Control
class_name ResumeViewer

signal on_hire_attempted(employee_data: Employee)
signal on_rejected(employee_data: Employee)
signal on_empty() # 当所有简历都被处理完时发出

@onready var left_arrow = $VBoxContainer/HBoxContainer/LeftArrow
@onready var right_arrow = $VBoxContainer/HBoxContainer/RightArrow
@onready var cards_container = $VBoxContainer/HBoxContainer/CardsContainer # 🌟 新增的容器
@onready var reject_all_btn = $VBoxContainer/MarginContainer/OpreateAll/RejectAll
@onready var accept_all_btn = $VBoxContainer/MarginContainer/OpreateAll/AcceptAll
@onready var yes_sound: AudioStreamPlayer = $YesSound
@onready var no_sound: AudioStreamPlayer = $NoSound

var current_resumes: Array[Employee] = []
var current_page: int = 0

const ITEMS_PER_PAGE: int = 3 # 🌟 一页展示几张
const YES_NO_PANEL_SCENE = preload("res://scenes/UI/custom/popup_window.tscn")

func _ready():
	left_arrow.pressed.connect(_on_left_pressed)
	right_arrow.pressed.connect(_on_right_pressed)
	
	for slot in cards_container.get_children():
		if slot is ResumeSlot: # 前提是你在 resume_slot.gd 顶部写了 class_name ResumeSlot
			slot.hire_requested.connect(_on_slot_hire_requested)
			slot.reject_requested.connect(_on_slot_reject_requested)
	
	reject_all_btn.add_to_group("reject_buttons")
	
	# 看大总管脸色行事
	if Gamemanager.is_reject_button_disabled:
		reject_all_btn.disabled = true # 💥 进场直接变灰禁用！
		
	_init_opreate_all_buttons()
	
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
	yes_sound.play()

func _on_slot_reject_requested(emp: Employee):
	on_rejected.emit(emp)
	remove_employee(emp)
	no_sound.play()

func _init_opreate_all_buttons() -> void:
	if reject_all_btn:
		reject_all_btn.pressed.connect(_on_reject_all_pressed)
	if accept_all_btn:
		accept_all_btn.pressed.connect(_on_accept_all_pressed)

func _on_reject_all_pressed() -> void:
	if current_resumes.is_empty():
		return
		
	# 1. 检查当前列表里有没有高贵的 SSR
	var has_ssr: bool = false
	for emp in current_resumes:
		if emp.rarity == Employee.Rarity.SSR:
			has_ssr = true
			break # 抓到一个就触发熔断
			
	# 2. 风控判定：有 SSR 就跳出二级弹窗
	if has_ssr:
		_show_ssr_warning_popup()
	else:
		# 全是普通打工人，直接一键全拒
		_do_actual_reject_all()

# 点击【接收所有】
func _on_accept_all_pressed() -> void:
	if current_resumes.is_empty():
		return
	
	# 1. 预检总成本
	var total_cost = 0
	for emp in current_resumes:
		total_cost += RecruitmentManager.calculate_hire_cost(emp)
	
	# 2. 判断 KPI
	if Gamemanager.kpi >= total_cost:
		print("大赦天下！全都要了！")
		
		# 3. 稳妥招募：复制名单，挨个触发招募信号
		var temp_list = current_resumes.duplicate()
		for emp in temp_list:
			on_hire_attempted.emit(emp)
		if EmployeeManager.has_method("hire_employees_batch"):
			EmployeeManager.hire_employees_batch(temp_list)	
		# 招募完后清空列表
		current_resumes.clear()
		current_page = 0
		_update_display()
	else:
		# 4. 钱不够时：什么都不做，只弹出提示
		print("【招聘中心】KPI 不足，全招募失败！")

		var panel = get_tree().get_first_node_in_group("recruitment_panel")
		if panel and panel.has_method("show_floating_tip"):
			panel.show_floating_tip("INGAME_TIP_NOT_ENOUGH_HIRE_COUNT")


func _do_actual_reject_all() -> void:
	print("正在一键拒绝所有员工...")
	
	# 🌟 复制一份数组，挨个通知外部：“这些人被拒了啊！”（为了触发你们可能的拒绝统计或KPI扣除）
	var temp_list = current_resumes.duplicate()
	for emp in temp_list:
		on_rejected.emit(emp)
		
	# 斩草除根，清空本地池子，复位页码，更新显示
	current_resumes.clear()
	current_page = 0
	_update_display()

func _show_ssr_warning_popup() -> void:
	# 1. 实例化你的弹窗
	var popup = YES_NO_PANEL_SCENE.instantiate()
	
	# 2. 🌟 灵魂一步：利用它自带的 @export set 拦截器，直接优雅赋值！
	# 这样哪怕节点还没进入场景树，值也已经安全塞进去了
	popup.title_text = "Are you sure to reject SSR resume？"
	popup.confirm_label = "Yes"  # 把 QUIT 改成接地气的中文
	popup.cancel_label = "No" # 把 CANCEL 改成点错了
	
	# 3. 把弹窗丢进当前场景（让它居中置顶显示）
	add_child(popup)
	
	# 如果你的预制体本身没做居中锚点，可以在这里用代码强行把它按在全屏正中央
	if popup is Control:
		popup.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

	# 4. 🌟 精准偷听信号：对接确认窗口发出的自定义信号
	popup.confirmed.connect(func():
		_do_actual_reject_all() # 玩家铁了心不要，执行全拒
		popup.queue_free()      # 斩草除根，销毁弹窗（用 queue_free 彻底释放内存，比单纯 hide 更好）
	)
	
	popup.canceled.connect(func():
		print("玩家后悔了，成功保住 SSR！")
		popup.queue_free()      # 点错了，直接人间蒸发，不留痕迹
	)
