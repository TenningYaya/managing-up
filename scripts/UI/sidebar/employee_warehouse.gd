#employee_warehouse.gd
extends Control

# 把你做的卡片 Scene 拖到右侧 Inspector 的这个变量里
@export var card_scene: PackedScene 
@onready var grid = $ScrollContainer/GridContainer

func _ready() -> void:
	# 这一行必须有，且 EmployeeManager 必须是 Autoload 的单例名
	EmployeeManager.employee_added.connect(_on_employee_hired)
	EmployeeManager.employee_removed.connect(_on_employee_fired)
	hide()
	
func _on_employee_hired(new_employee: Employee) -> void:
	var card_instance = card_scene.instantiate()
	# 【关键修改】：先加进 GridContainer
	grid.add_child(card_instance) 
	# 【然后再喂数据】：此时 @onready 已经跑过了，节点不再是 Nil
	card_instance.setup_card(new_employee)
	card_instance.name = new_employee.employee_name 
	
	card_instance.card_clicked.connect(_on_card_selected)

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
	show()
	# 可以在这里刷新一遍显示，确保数据最新
