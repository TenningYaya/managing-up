#employee_warehouse.gd
extends Control

# 把你做的卡片 Scene 拖到右侧 Inspector 的这个变量里
@export var card_scene: PackedScene 
@onready var grid = $ScrollContainer/GridContainer
@onready var sort_menu: OptionButton = $VBoxContainer/SortMenu

@onready var select_toggle_btn = $VBoxContainer/Select # 仓库右上的“选择”按钮
@onready var bottom_op_bar = $BottomOperationBar     # 底部三个按钮的容器
@onready var bulk_optimize_btn = $BottomOperationBar/Fire
@onready var bulk_recall_btn = $BottomOperationBar/Recall
@onready var bulk_dispatch_btn = $BottomOperationBar/Dispatch
@onready var bulk_fire_popup = $BulkFirePopup
@onready var bulk_select_all_btn = $BottomOperationBar/SelectAll

@onready var warehouse_sfx = $Warehouse

var is_selection_mode: bool = false
var selected_employees: Array[Employee] = []

var dragging = false
var drag_offset = Vector2()

var sort_options = [
	{"key": "WAREHOUSE_SORT_STATS_HIGH", "id": 0},
	{"key": "WAREHOUSE_SORT_STATS_LOW", "id": 1},
	{"key": "WAREHOUSE_SORT_HIRE_NEWEST", "id": 2},
	{"key": "WAREHOUSE_SORT_HIRE_OLDEST", "id": 3}
]

func _ready() -> void:
	# 这一行必须有，且 EmployeeManager 必须是 Autoload 的单例名
	EmployeeManager.employee_added.connect(_on_employee_hired)
	EmployeeManager.employee_removed.connect(_on_employee_fired)

	# 仓库被打开（变可见）时播放音效。挂在 visibility_changed 上而不是某个 open 函数里，
	# 这样无论从哪条入口打开（open_warehouse / currency_ui / recruitment_panel 直接 show）都会响。
	visibility_changed.connect(_on_visibility_changed)
	
	# 1. 初始化下拉菜单选项
	sort_menu.clear()


# 2. 循环添加
	sort_menu.clear()
	for opt in sort_options:
		# tr(opt.key) 会自动根据当前语言查出对应的文字（比如“属性最高”）
		sort_menu.add_item(tr(opt.key), opt.id)
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
	bulk_select_all_btn.pressed.connect(_on_bulk_select_all_pressed)
	
	# 初始化 UI 状态
	bottom_op_bar.hide()
	_update_bulk_buttons_state()
	
	Gamemanager.request_employee_drop.connect(_on_map_needs_refresh)
	EmployeeManager.employee_removed.connect(_on_map_needs_refresh)
	EmployeeManager.employee_map_status_changed.connect(_on_map_needs_refresh)
	sort_menu.alignment = HORIZONTAL_ALIGNMENT_CENTER
	
func _unhandled_input(event: InputEvent) -> void:
	# 如果仓库本来就没开，或者现在正弹着确认窗，直接无视点击逻辑
	if not visible or (bulk_fire_popup and bulk_fire_popup.visible):
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 判定点击是否在仓库外面
		if not get_global_rect().has_point(event.global_position):
			# 还有一个关键：如果点的是弹窗区域，也不准缩回去
			if bulk_fire_popup and bulk_fire_popup.get_global_rect().has_point(event.global_position):
				return
				
			hide()
			# 如果你有侧边栏状态，记得这里也要同步重置（可选）
			
func _on_visibility_changed() -> void:
	# 只在“变为可见”时响一次；hide() 时 visible=false，不播放
	if visible and warehouse_sfx:
		warehouse_sfx.play()


# 语言切换时重建排序下拉的选项文字（OptionButton 的 item 文字是 tr 写死的，不会自动刷新）
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		var sel := sort_menu.selected
		sort_menu.clear()
		for opt in sort_options:
			sort_menu.add_item(tr(opt.key), opt.id)
		sort_menu.select(maxi(sel, 0))


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
		btn_label.text = tr("WAREHOUSE_CANCEL") if is_selection_mode else tr("WAREHOUSE_SELECT")
	
func _on_employee_hired(new_employee: Employee) -> void:
	var card_instance = card_scene.instantiate()
	# 【关键修改】：先加进 GridContainer
	grid.add_child(card_instance) 
	# 【然后再喂数据】：此时 @onready 已经跑过了，节点不再是 Nil
	card_instance.setup_card(new_employee)
	#card_instance.name = new_employee.employee_name 
	
	if card_instance.has_method("update_on_map_status"):
		card_instance.update_on_map_status()
		
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
	for card in grid.get_children():
		if card.get("my_employee_data") == fired_employee:
			card.queue_free()
			break
		
# 模拟抽卡/获得新员工后添加到仓库
func add_employee_to_warehouse(new_employee_data: Employee):
	# 1. 实例化一张空卡片
	var card_instance = card_scene.instantiate()
	
	# 2. 把数据填进卡片
	card_instance.setup_card(new_employee_data)
	
	# 3. 把卡片塞进网格里 (它会自动排到正确的位置)
	grid.add_child(card_instance)

# 刚才在 recruitment_panel 里留空的按钮方法
func open_warehouse():
	refresh_display() # 打开时根据当前选择的排序刷新一次
	show()  # 变可见会自动触发 _on_visibility_changed 播放音效

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
	
	# 4. 重新生成
	for emp in sorted_data:
		var card = card_scene.instantiate()
		grid.add_child(card)
		card.setup_card(emp)
		#card.name = emp.employee_name
		if card.has_method("update_on_map_status"):
			card.update_on_map_status()
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
		var card_emp = card.get("my_employee_data")
		if card_emp != null:
			# 🌟 核心：只认身份证号，不管名字是不是叫 Marry！
			if card_emp.get_instance_id() == emp.get_instance_id():
				card.is_selected = selected_employees.has(emp)
				
				# 🌟 修复二：不要 break！有时候重新排列或刷新时，
				# UI 列表里可能残留着没清理干净的影子卡片。
				# 不 break 能确保所有绑定了这个人的卡片都能更新状态。
			
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
		if emp.get("current_seat") != null:
			emp.current_seat.clear_occupant()
			emp.current_seat = null
			
		# --- B. 施加封印（直接收回地图实体）---
		# 因为 emp 就是地图上的那个实体，不需要去遍历查找！
		if emp.has_method("set_inactive"):
			emp.set_inactive()
		else:
			# 如果你还没在 Employee.gd 里写 set_inactive，就直接在这里写保底逻辑：
			emp.visible = false
			emp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			emp.process_mode = PROCESS_MODE_DISABLED
			if emp.is_in_group("dropped_employee"):
				emp.remove_from_group("dropped_employee")
			if emp.get_parent():
				emp.get_parent().remove_child(emp)
	
	# --- C. 退出模式并刷新 ---
	_toggle_selection_mode() 
	_on_map_needs_refresh()

# 2. 批量 Dispatch (派遣)
func _on_bulk_dispatch_pressed():
	print("批量派遣员工，数量：", selected_employees.size())
	for emp in selected_employees:
		# 只有不在地图上的才发信号
		if not _check_emp_on_map(emp):
			Gamemanager.request_employee_drop.emit(emp)
			emp.visible = true
			emp.mouse_filter = Control.MOUSE_FILTER_STOP
			emp.process_mode = PROCESS_MODE_INHERIT
	_toggle_selection_mode()
	_on_map_needs_refresh()

# 3. 批量优化 (开除)
func _on_bulk_optimize_pressed():
	if selected_employees.is_empty(): return
	
	# 1. 设置弹窗内容
	var title_template = tr("WAREHOUSE_BULK_FIRE_TITLE")
	bulk_fire_popup.title_text = title_template.format({"n": selected_employees.size()})
	
	bulk_fire_popup.confirm_label = tr("WAREHOUSE_BULK_FIRE_CONFIRM")
	bulk_fire_popup.cancel_label = tr("WAREHOUSE_BULK_FIRE_CANCEL")
	
	# 2. 连接信号（因为是专属弹窗，_ready里连一次就行，或者这里用简易连接）
	# 稳妥起见，先断开旧连接防止重复
	if bulk_fire_popup.confirmed.is_connected(_execute_bulk_fire):
		bulk_fire_popup.confirmed.disconnect(_execute_bulk_fire)
	
	bulk_fire_popup.confirmed.connect(_execute_bulk_fire, CONNECT_ONE_SHOT)
	
	# 3. 显示弹窗
	bulk_fire_popup.show()

func _execute_bulk_fire():
	print("执行批量开除...")
	var to_fire = selected_employees.duplicate()
	
	for emp in to_fire:
		# 1. 工位处理：如果有座位，先让座位空出来
		if emp.get("current_seat") != null:
			emp.current_seat.clear_occupant()
			emp.current_seat = null
			
		# 2. 系统记录移除：通知仓库和管理器
		EmployeeManager.employee_removed.emit(emp)
		EmployeeManager.my_employees.erase(emp)
		
		# 3. 彻底销毁：这一行会同时把地图上的小人、仓库的数据、内存的对象全部物理抹除
		if is_instance_valid(emp):
			emp.queue_free()
	
	# 4. UI 刷新
	selected_employees.clear()
	_toggle_selection_mode()
	refresh_display()       # 重新生成列表，已开除的人就不会出现了
	_on_map_needs_refresh() # 刷新剩下的人的小绿标
	bulk_fire_popup.hide()

func _on_bulk_select_all_pressed() -> void:
	# 先数数当前网格里有多少张有效卡片
	var total_cards = grid.get_child_count()
	if total_cards == 0:
		return
		
	# 如果当前选中的人数等于卡片总数，说明已经是“全选”状态了，那么这次点击就是“取消全选”
	if selected_employees.size() == total_cards:
		selected_employees.clear()
		# 遍历所有卡片，取消勾选效果
		for card in grid.get_children():
			card.is_selected = false
	else:
		# 否则，就是执行“全选”操作
		selected_employees.clear() # 先清空，防止有重复的
		for card in grid.get_children():
			var emp_data = card.get("my_employee_data")
			if emp_data != null:
				selected_employees.append(emp_data)
				card.is_selected = true # 强制点亮
				
	# 最后，别忘了更新底下一排开除/外派按钮的状态（比如全取消后要变灰）
	_update_bulk_buttons_state()
	
# 辅助判定（逻辑同 Panel）
func _check_emp_on_map(emp: Employee) -> bool:
	if emp == null: return false
	
	# 判定 1：有工位
	if emp.get("current_seat") != null: 
		return true
		
	# 判定 2：在掉落组里且在树里
	if emp.is_in_group("dropped_employee") and emp.is_inside_tree():
		return true
		
	return false

func _on_title_bar_gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			drag_offset = get_global_mouse_position() - global_position
			
	if event is InputEventMouseMotion and dragging:
		var target: Vector2 = get_global_mouse_position() - drag_offset
		var vp := get_viewport_rect().size
		# 限制在游戏窗口内：拖到边缘就停，不能跑出窗口外变半透明
		target.x = clampf(target.x, 0.0, maxf(0.0, vp.x - size.x))
		target.y = clampf(target.y, 0.0, maxf(0.0, vp.y - size.y))
		global_position = target


func _on_close_panel_pressed() -> void:
	self.hide()
