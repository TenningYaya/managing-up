#employee_warehouse.gd
extends Control

# 把你做的卡片 Scene 拖到右侧 Inspector 的这个变量里
@export var card_scene: PackedScene 
@onready var grid = $ScrollContainer/GridContainer
@onready var sort_menu: OptionButton = $SortMenu

@onready var select_toggle_btn = $Select # 仓库右上的“选择”按钮
@onready var bottom_op_bar = $BottomOperationBar     # 底部三个按钮的容器
@onready var bulk_optimize_btn = $BottomOperationBar/Fire
@onready var bulk_recall_btn = $BottomOperationBar/Recall
@onready var bulk_dispatch_btn = $BottomOperationBar/Dispatch

var is_selection_mode: bool = false
var selected_employees: Array[Employee] = []

func _ready() -> void:
	# 这一行必须有，且 EmployeeManager 必须是 Autoload 的单例名
	EmployeeManager.employee_added.connect(_on_employee_hired)
	EmployeeManager.employee_removed.connect(_on_employee_fired)
	
	# 1. 初始化下拉菜单选项
	sort_menu.clear()
	sort_menu.add_item("属性总和：从高到低", 0)
	sort_menu.add_item("属性总和：从低到高", 1)
	sort_menu.add_item("入职时间：最晚优先", 2)
	sort_menu.add_item("入职时间：最早优先", 3)
	sort_menu.select(0)
	# 2. 绑定切换事件
	sort_menu.item_selected.connect(_on_sort_selected)
	refresh_display()
	hide()
	
	select_toggle_btn.pressed.connect(_toggle_selection_mode)
	
	# 绑定批量按钮
	bulk_optimize_btn.pressed.connect(_on_bulk_optimize_pressed)
	bulk_recall_btn.pressed.connect(_on_bulk_recall_pressed)
	bulk_dispatch_btn.pressed.connect(_on_bulk_dispatch_pressed)
	
	# 初始化 UI 状态
	bottom_op_bar.hide()
	_update_bulk_buttons_state()
	
	Gamemanager.request_employee_drop.connect(_on_map_needs_refresh)
	EmployeeManager.employee_removed.connect(_on_map_needs_refresh)

func _on_map_needs_refresh(_data = null):
	# 给 0.1 秒等节点树删干净，然后全体起立！
	get_tree().create_timer(0.1).timeout.connect(refresh_all_card_icons)

func refresh_all_card_icons():
	# 仓库统一指挥：所有卡片，现在，立刻，更新图标！
	for card in grid.get_children():
		if card.has_method("update_on_map_status"):
			card.update_on_map_status()
			
# 切换选择模式
func _toggle_selection_mode():
	is_selection_mode = !is_selection_mode
	selected_employees.clear()
	
	# 通知所有名片进入/退出选择模式
	for card in grid.get_children():
		if card.has_method("set_selection_mode"):
			card.set_selection_mode(is_selection_mode)
	
	bottom_op_bar.visible = is_selection_mode
	_update_bulk_buttons_state()
	
	var btn_label = select_toggle_btn.get_node("Label")
	if btn_label:
		btn_label.text = "Cancel" if is_selection_mode else "Select"
	
func _on_employee_hired(new_employee: Employee) -> void:
	var card_instance = card_scene.instantiate()
	# 【关键修改】：先加进 GridContainer
	grid.add_child(card_instance) 
	# 【然后再喂数据】：此时 @onready 已经跑过了，节点不再是 Nil
	card_instance.setup_card(new_employee)
	card_instance.name = new_employee.employee_name 
	
	card_instance.card_clicked.connect(_on_card_selected)
	if visible:
		refresh_display()
		
func _on_card_selected(emp_data: Employee):
	if is_selection_mode:
		_toggle_employee_selection(emp_data)
	else:
		# 原有的打开面板逻辑
		var panel = get_tree().get_first_node_in_group("employee_panel")
		if panel: panel.open_panel(emp_data)
		
func _on_employee_fired(fired_employee: Employee) -> void:
	# 在网格里找到对应名字的名片，然后删除
	var card = grid.get_node_or_null(fired_employee.employee_name)
	if card:
		card.queue_free()
		
# 模拟抽卡/获得新员工后添加到仓库
func add_employee_to_warehouse(new_employee_data: Employee):
	# 1. 实例化一张空卡片
	var card_instance = card_scene.instantiate()
	
	# 2. 把数据填进卡片
	card_instance.setup_card(new_employee_data)
	
	# 3. 把卡片塞进网格里 (它会自动排到正确的位置)
	grid.add_child(card_instance)
	
func _input(event: InputEvent) -> void:
	if visible and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 直接判定当前脚本所在的这个节点（根节点）
		if not get_global_rect().has_point(event.global_position):
			hide()

# 刚才在 recruitment_panel 里留空的按钮方法
func open_warehouse():
	refresh_display() # 打开时根据当前选择的排序刷新一次
	show()

func refresh_display():
	# 1. 【彻底清理】：不仅是排队销毁，而是立刻从网格中移除
	for child in grid.get_children():
		grid.remove_child(child) # 先踢出网格，防止干扰排序
		child.queue_free()      # 再彻底销毁
	
	# 2. 【显式获取 ID】：OptionButton 的 get_item_id 更保险
	var selected_idx = sort_menu.selected
	if selected_idx == -1: selected_idx = 0 # 保底逻辑
	
	# 获取你在 add_item 时填写的那个 ID (0, 1, 2, 3)
	var sort_id = sort_menu.get_item_id(selected_idx)
	var current_sort = sort_id as EmployeeManager.SortType
	
	# 3. 获取数据
	var sorted_data = EmployeeManager.get_sorted_employees(current_sort)
	print("当前排序类型: ", current_sort, " 第一名员工: ", sorted_data[0].employee_name if sorted_data.size() > 0 else "空")
	
	# 4. 重新生成
	for emp in sorted_data:
		var card = card_scene.instantiate()
		grid.add_child(card)
		card.setup_card(emp)
		card.name = emp.employee_name
		# 别忘了连信号
		if not card.card_clicked.is_connected(_on_card_selected):
			card.card_clicked.connect(_on_card_selected)

func _on_sort_selected(_index: int):
	refresh_display()

func _toggle_employee_selection(emp: Employee):
	if selected_employees.has(emp):
		selected_employees.erase(emp)
	else:
		selected_employees.append(emp)
	
	# 刷新名片的选中视觉效果
	for card in grid.get_children():
		if card.name == emp.employee_name:
			card.is_selected = selected_employees.has(emp)
			break
			
	_update_bulk_buttons_state()

func _update_bulk_buttons_state():
	var has_selection = selected_employees.size() > 0
	
	# 设置禁用状态
	bulk_optimize_btn.disabled = !has_selection
	bulk_recall_btn.disabled = !has_selection
	bulk_dispatch_btn.disabled = !has_selection
	
	# 加个视觉反馈：不能点的时候变半透明
	var alpha = 1.0 if has_selection else 0.5
	bulk_optimize_btn.modulate.a = alpha
	bulk_recall_btn.modulate.a = alpha
	bulk_dispatch_btn.modulate.a = alpha

# ================= 批量操作业务逻辑 =================

func _on_bulk_recall_pressed():
	print("批量收回员工，数量：", selected_employees.size())
	
	for emp in selected_employees:
		# --- A. 清理工位 ---
		if emp.current_seat != null:
			emp.current_seat.clear_occupant()
			emp.current_seat = null
			
		# --- B. 寻找并清理地图实体 ---
		var dropped_nodes = get_tree().get_nodes_in_group("dropped_employee")
		for node in dropped_nodes:
			if node.name == emp.employee_name:
				# 🚨 【核心修复 1】：先手动踢出组！
				# 否则在当前帧，名片自查时依然能通过组名找到这个“还没死透”的小人
				node.remove_from_group("dropped_employee")
				node.queue_free()
				break
	
	# --- C. 退出模式 ---
	_toggle_selection_mode() 
	
	# 🚨 【核心修复 2】：手动触发刷新通知！
	# 因为这里是批量操作，循环结束后喊一嗓子，让所有名片整齐划一地重检图标
	_on_map_needs_refresh()

# 2. 批量 Dispatch (派遣)
func _on_bulk_dispatch_pressed():
	print("批量派遣员工，数量：", selected_employees.size())
	for emp in selected_employees:
		# 只有不在地图上的才发信号
		if not _check_emp_on_map(emp):
			Gamemanager.request_employee_drop.emit(emp)
	_toggle_selection_mode()
	_on_map_needs_refresh()

# 3. 批量优化 (开除)
func _on_bulk_optimize_pressed():
	# 借用一下 EmployeePanel 的 PopupWindow (或者你自己再做一个通用的)
	var panel = get_tree().get_first_node_in_group("employee_panel")
	if panel:
		var popup = panel.popup_window
		popup.title_text = "Optimize these " + str(selected_employees.size()) + " employees?"
		# 这里需要注意：execute_fire 现在是针对单人的，批量需要重新连接信号
		if popup.confirmed.is_connected(panel.execute_fire_employee):
			popup.confirmed.disconnect(panel.execute_fire_employee)
		
		# 连接批量开除方法
		if not popup.confirmed.is_connected(_execute_bulk_fire):
			popup.confirmed.connect(_execute_bulk_fire, CONNECT_ONE_SHOT)
		popup.show()

func _execute_bulk_fire():
	# 倒序删除防止索引出问题（虽然这里是用的数据引用）
	var to_fire = selected_employees.duplicate()
	for emp in to_fire:
		# 逻辑完全复用单人开除：
		if emp.current_seat != null: emp.current_seat.clear_occupant()
		
		var dropped_nodes = get_tree().get_nodes_in_group("dropped_employee")
		for node in dropped_nodes:
			if node.name == emp.employee_name:
				node.queue_free()
				break
				
		EmployeeManager.employee_removed.emit(emp)
		EmployeeManager.my_employees.erase(emp)
		emp.queue_free()
	
	selected_employees.clear()
	_toggle_selection_mode()
	refresh_display() # 刷新仓库列表

# 辅助判定（逻辑同 Panel）
func _check_emp_on_map(emp: Employee) -> bool:
	if emp.current_seat != null: return true
	var dropped_nodes = get_tree().get_nodes_in_group("dropped_employee")
	for node in dropped_nodes:
		if node.name == emp.employee_name: return true
	return false
