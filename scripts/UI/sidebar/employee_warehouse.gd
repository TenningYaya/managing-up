#employee_warehouse.gd
extends Control

# 把你做的卡片 Scene 拖到右侧 Inspector 的这个变量里
@export var card_scene: PackedScene 
@onready var grid = $ScrollContainer/GridContainer

func _ready() -> void:
	# 这一行必须有，且 EmployeeManager 必须是 Autoload 的单例名
	EmployeeManager.employee_added.connect(_on_employee_hired)
	
func _on_employee_hired(new_employee: Employee) -> void:
	var card_instance = card_scene.instantiate()
	# 【关键修改】：先加进 GridContainer
	grid.add_child(card_instance) 
	# 【然后再喂数据】：此时 @onready 已经跑过了，节点不再是 Nil
	card_instance.setup_card(new_employee)
	card_instance.name = new_employee.employee_name 

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
