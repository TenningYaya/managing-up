#employee_panel.gd
extends Control
class_name EmployeePanel

# ==========================================
# 1. 节点引用 (严格对应截图层级)
# ==========================================
@onready var click_blocker: ColorRect = $ClickBlocker

# --- 员工信息部分 ---
@onready var figure: TextureRect = $PanelBg/EmployeePage/NameCard/Figure
@onready var name_label: Label = $PanelBg/EmployeePage/NameCard/VBoxContainer/NameLabel
@onready var rarity_label: Label = $PanelBg/EmployeePage/NameCard/VBoxContainer/RarityLabel

# --- 属性条组件部分 ---
@onready var efficiency_bar: EmployeeAbility = $PanelBg/EmployeePage/Information/Abilities/EfficiencyBar
@onready var quality_bar: EmployeeAbility = $PanelBg/EmployeePage/Information/Abilities/QualityBar
@onready var experience_bar: EmployeeAbility = $PanelBg/EmployeePage/Information/Abilities/ExperienceBar

@onready var progress_bar: TextureProgressBar = $PanelBg/EmployeePage/Information/ProgressBar

# --- 底部按钮部分 ---
@onready var dispatch_btn: TextureButton = $PanelBg/EmployeePage/Manage/DispatchButton
@onready var fire_btn: TextureButton = $PanelBg/EmployeePage/Manage/NormalButton2 # 建议之后重命名为 FireButton
@onready var dispatch_btn_label: Label = $PanelBg/EmployeePage/Manage/DispatchButton/Label

# --- 弹窗部分 ---
@onready var popup_window = $PanelBg/PopupWindow

# 当前正在查看的员工数据引用
var current_employee: Employee = null

# ==========================================
# 2. 初始化
# ==========================================
func _ready() -> void:
	hide() 
	popup_window.hide()
	
	click_blocker.gui_input.connect(_on_click_blocker_input)
	
	# 绑定底部按钮事件
	dispatch_btn.pressed.connect(_on_dispatch_pressed)
	fire_btn.pressed.connect(_on_fire_pressed)
	# ------------------------------------------
	# 3. 这里是连接 PopupWindow 的地方！
	# ------------------------------------------
	# 当 PopupWindow 发出 confirmed 信号时，执行开除逻辑
	popup_window.confirmed.connect(execute_fire_employee)
	
	# 当 PopupWindow 发出 canceled 信号时，执行取消逻辑（可选）
	popup_window.canceled.connect(cancel_fire_employee)

func open_panel(employee: Employee) -> void:
	if employee == null:
		return
		
	current_employee = employee
	
	# 刷新文本
	name_label.text = employee.employee_name
	
	match employee.rarity:
		Employee.Rarity.R: rarity_label.text = "R"
		Employee.Rarity.SR: rarity_label.text = "SR"
		Employee.Rarity.SSR: rarity_label.text = "SSR"
	
	# 调用我们刚写的 EmployeeAbility 组件函数来赋值
	efficiency_bar.set_value(employee.efficiency)
	quality_bar.set_value(employee.quality)
	experience_bar.set_value(employee.experience)
	
	# 刷新按钮状态
	_update_dispatch_button()
	
	popup_window.hide()
	show()

func close_panel() -> void:
	current_employee = null
	hide()

func _on_click_blocker_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_panel()

# ==========================================
# 4. 外派与调入逻辑
# ==========================================
func _update_dispatch_button() -> void:
	if current_employee.current_seat != null:
		dispatch_btn_label.text = "Dispatch"
	else:
		dispatch_btn_label.text = "Recall"

func _on_dispatch_pressed() -> void:
	if current_employee == null: return
	
	if current_employee.current_seat != null:
		current_employee.current_seat.clear_occupant()
		current_employee.current_seat = null
	else:
		print("请直接拖拽员工到工位上！")
		
	_update_dispatch_button()

# ==========================================
# 5. 优化(开除)弹窗逻辑
# ==========================================
func _on_fire_pressed() -> void:
# 在显示弹窗前，动态设置一下文本（利用你写的 set 属性）
	popup_window.title_text = "Are you sure to fire " + current_employee.employee_name + " 吗？"
	popup_window.confirm_label = "Sure"
	popup_window.cancel_label = "Wait"
	popup_window.show()

# ⚠️ 注意：你需要将你的 PopupWindow 里的“确认”按钮信号连接到这个函数！
func execute_fire_employee() -> void:
	if current_employee != null:
		# 1. 腾出工位
		if current_employee.current_seat != null:
			current_employee.current_seat.clear_occupant()
		
		# 2. 返还资源的逻辑 (GDD: SR和SSR返还少量美金)
		if current_employee.rarity == Employee.Rarity.SR or current_employee.rarity == Employee.Rarity.SSR:
			print("退还了少量美金！")
			
		# 3. 删除员工实例
		current_employee.queue_free()
		
	popup_window.hide()
	close_panel()

# ⚠️ 注意：你需要将你的 PopupWindow 里的“取消”按钮信号连接到这个函数！
func cancel_fire_employee() -> void:
	popup_window.hide()
