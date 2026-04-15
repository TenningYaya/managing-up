#employee_manager.gd
extends Node

# ==========================================
# 信号 (Signals)：发生变化时通知全服
# ==========================================
signal money_changed(current_money: int)
signal employee_added(employee_data: Employee)
signal employee_removed(employee_data: Employee)

# ==========================================
# 核心数据 (Data)
# ==========================================
var current_money: int = 1000 # 初始启动资金
var my_employees: Array[Employee] = [] # 玩家拥有的所有员工列表

func _ready() -> void:
	# 游戏启动时，广播一下初始资金
	call_deferred("emit_signal", "money_changed", current_money)

# ==========================================
# 资源管理API (管钱)
# ==========================================
# 赚到钱了 (比如员工产出文件后调用这个)
func add_money(amount: int) -> void:
	current_money += amount
	money_changed.emit(current_money)
	print("赚了 $", amount, "，当前余额 $", current_money)

# 花钱 (抽卡系统会调用这个来扣钱)
func spend_money(amount: int) -> bool:
	if current_money >= amount:
		current_money -= amount
		money_changed.emit(current_money)
		print("花了 $", amount, "，当前余额 $", current_money)
		return true
	else:
		print("余额不足！需要 $", amount, "，只有 $", current_money)
		return false

# ==========================================
# 员工名册管理API (管人)
# ==========================================
# 录用新员工
func hire_employee(new_employee: Employee) -> void:
	if new_employee not in my_employees:
		my_employees.append(new_employee)
		employee_added.emit(new_employee) # 通知仓库去生成UI名片
		print("录用了新同事: ", new_employee.employee_name)

# 解雇/优化员工
func fire_employee(employee: Employee) -> void:
	if employee in my_employees:
		my_employees.erase(employee)
		employee_removed.emit(employee)
		# 如果他还在座位上，记得让他腾出座位 (调用之前写的 clear_occupant)
		if employee.current_seat != null:
			employee.current_seat.clear_occupant()
		
		# 释放节点内存
		employee.queue_free() 
		print("开除了同事: ", employee.employee_name)

# 一键开除所有
func fire_all_employees() -> void:
	# 倒序遍历删除，防止数组越界报错
	for i in range(my_employees.size() - 1, -1, -1):
		fire_employee(my_employees[i])
