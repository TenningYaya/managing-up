extends CanvasLayer
class_name EmployeePanel

# ==========================================
# 1. 节点引用
# ==========================================
@onready var figure: TextureRect = $PanelBg/EmployeePage/NameCard/Figure
@onready var name_label: Label = $PanelBg/EmployeePage/NameCard/VBoxContainer/NameLabel
@onready var rarity_label: Label = $PanelBg/EmployeePage/NameCard/VBoxContainer/RarityLabel

@onready var efficiency_bar: EmployeeAbility = $PanelBg/EmployeePage/Information/Abilities/EfficiencyBar
@onready var quality_bar: EmployeeAbility = $PanelBg/EmployeePage/Information/Abilities/QualityBar
@onready var experience_bar: EmployeeAbility = $PanelBg/EmployeePage/Information/Abilities/ExperienceBar

@onready var progress_bar: TextureProgressBar = $PanelBg/EmployeePage/Information/ProgressBar

@onready var dispatch_btn: TextureButton = $PanelBg/EmployeePage/Manage/DispatchButton
@onready var fire_btn: TextureButton = $PanelBg/EmployeePage/Manage/NormalButton2
@onready var dispatch_btn_label: Label = $PanelBg/EmployeePage/Manage/DispatchButton/Label

@onready var popup_window = $PanelBg/PopupWindow

var current_employee: Employee = null

# ==========================================
# 2. 初始化
# ==========================================
func _ready() -> void:
	hide()
	popup_window.hide()

	progress_bar.min_value = 0
	progress_bar.max_value = 100
	progress_bar.value = 0

	dispatch_btn.pressed.connect(_on_dispatch_pressed)
	fire_btn.pressed.connect(_on_fire_pressed)

	popup_window.confirmed.connect(execute_fire_employee)
	popup_window.canceled.connect(cancel_fire_employee)

# ==========================================
# 3. 打开与关闭面板
# ==========================================
func open_panel(employee: Employee) -> void:
	if employee == null:
		return

	# 先断开旧员工
	_disconnect_current_employee()

	current_employee = employee

	# 刷新静态内容
	name_label.text = employee.employee_name

	match employee.rarity:
		Employee.Rarity.R:
			rarity_label.text = "R"
		Employee.Rarity.SR:
			rarity_label.text = "SR"
		Employee.Rarity.SSR:
			rarity_label.text = "SSR"

	efficiency_bar.set_value(employee.efficiency)
	quality_bar.set_value(employee.quality)
	experience_bar.set_value(employee.experience)

	_update_dispatch_button()

	# 先显示当前已有进度
	_refresh_progress_bar()

	# 再连接信号
	_connect_current_employee()

	popup_window.hide()
	show()

	print("[EmployeePanel] open_panel -> ", employee.employee_name)
	print("[EmployeePanel] 初始进度 -> ", progress_bar.value)


func close_panel() -> void:
	_disconnect_current_employee()
	current_employee = null
	progress_bar.value = 0
	hide()

# ==========================================
# 4. 进度条联动
# ==========================================
func _connect_current_employee() -> void:
	if current_employee == null:
		return

	if not current_employee.work_progress_changed.is_connected(_on_work_progress_changed):
		current_employee.work_progress_changed.connect(_on_work_progress_changed)

	if not current_employee.work_started.is_connected(_on_work_started):
		current_employee.work_started.connect(_on_work_started)

	if not current_employee.work_stopped.is_connected(_on_work_stopped):
		current_employee.work_stopped.connect(_on_work_stopped)

	if not current_employee.work_cycle_completed.is_connected(_on_work_cycle_completed):
		current_employee.work_cycle_completed.connect(_on_work_cycle_completed)

	if not current_employee.tree_exiting.is_connected(_on_current_employee_tree_exiting):
		current_employee.tree_exiting.connect(_on_current_employee_tree_exiting)

	print("[EmployeePanel] 已连接进度信号 -> ", current_employee.employee_name)


func _disconnect_current_employee() -> void:
	if current_employee == null:
		return

	if current_employee.work_progress_changed.is_connected(_on_work_progress_changed):
		current_employee.work_progress_changed.disconnect(_on_work_progress_changed)

	if current_employee.work_started.is_connected(_on_work_started):
		current_employee.work_started.disconnect(_on_work_started)

	if current_employee.work_stopped.is_connected(_on_work_stopped):
		current_employee.work_stopped.disconnect(_on_work_stopped)

	if current_employee.work_cycle_completed.is_connected(_on_work_cycle_completed):
		current_employee.work_cycle_completed.disconnect(_on_work_cycle_completed)

	if current_employee.tree_exiting.is_connected(_on_current_employee_tree_exiting):
		current_employee.tree_exiting.disconnect(_on_current_employee_tree_exiting)


func _refresh_progress_bar() -> void:
	if current_employee == null:
		progress_bar.value = 0
		return

	progress_bar.value = current_employee.get_work_progress_percent()


func _on_work_progress_changed(progress_percent: float) -> void:
	progress_bar.value = progress_percent


func _on_work_started() -> void:
	progress_bar.value = 0
	print("[EmployeePanel] 员工开始工作")


func _on_work_stopped() -> void:
	progress_bar.value = 0
	print("[EmployeePanel] 员工停止工作")


func _on_work_cycle_completed(_reward_amount: int) -> void:
	progress_bar.value = 0
	print("[EmployeePanel] 一轮工作完成，进度归零")


func _on_current_employee_tree_exiting() -> void:
	current_employee = null
	progress_bar.value = 0
	hide()

# ==========================================
# 5. 外派与调入逻辑
# ==========================================
func _update_dispatch_button() -> void:
	if current_employee == null:
		return

	if current_employee.current_seat != null:
		dispatch_btn_label.text = "Dispatch"
	else:
		dispatch_btn_label.text = "Recall"


func _on_dispatch_pressed() -> void:
	if current_employee == null:
		return

	if current_employee.current_seat != null:
		current_employee.current_seat.clear_occupant()
		current_employee.current_seat = null

		# 员工被从工位拿下来时，立即停止显示进度
		progress_bar.value = 0
	else:
		print("请直接拖拽员工到工位上！")

	_update_dispatch_button()

# ==========================================
# 6. 开除弹窗逻辑
# ==========================================
func _on_fire_pressed() -> void:
	if current_employee == null:
		return

	popup_window.title_text = "Are you sure to fire " + current_employee.employee_name + " 吗？"
	popup_window.confirm_label = "Sure"
	popup_window.cancel_label = "Wait"
	popup_window.show()


func execute_fire_employee() -> void:
	if current_employee != null:
		if current_employee.current_seat != null:
			current_employee.current_seat.clear_occupant()

		if current_employee.rarity == Employee.Rarity.SR or current_employee.rarity == Employee.Rarity.SSR:
			print("退还了少量美金！")

		current_employee.queue_free()

	popup_window.hide()
	close_panel()


func cancel_fire_employee() -> void:
	popup_window.hide()
