#employee_warehouse.gd
extends Control

# 把你做的卡片 Scene 拖到右侧 Inspector 的这个变量里
@export var card_scene: PackedScene 
@onready var grid = $ScrollContainer/GridContainer
@onready var sort_menu: OptionButton = $SortMenu

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
	# 利用我们之前学到的“组检测”大法，直接喊出面板
	var panel = get_tree().get_first_node_in_group("employee_panel")
	if panel:
		panel.open_panel(emp_data)
		# hide() # 可选：如果你希望点开详情后，仓库自动关掉，就加这一行
	else:
		push_error("仓库：找不着员工面板！")
		
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
