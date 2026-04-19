# employee_manager.gd
extends Node

# ==========================================
# 信号 (Signals)：发生变化时通知全服
# ==========================================
signal employee_added(employee_data: Employee)
signal employee_removed(employee_data: Employee)

# ==========================================
# 核心数据 (Data)
# ==========================================
var my_employees: Array[Employee] = [] # 玩家拥有的所有员工列表
enum SortType { SUM_DESC, SUM_ASC, TIME_DESC, TIME_ASC }

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

func get_sorted_employees(type: SortType) -> Array[Employee]:
	var sorted_list = my_employees.duplicate() # 复制一份，不破坏原数组
	
	match type:
		SortType.SUM_DESC: # 属性总和从高到低
			sorted_list.sort_custom(func(a, b): 
				return (a.efficiency + a.quality + a.experience) > (b.efficiency + b.quality + b.experience)
			)
		SortType.SUM_ASC: # 属性总和从低到高
			sorted_list.sort_custom(func(a, b): 
				return (a.efficiency + a.quality + a.experience) < (b.efficiency + b.quality + b.experience)
			)
		SortType.TIME_DESC: # 入职时间倒序（晚来的在上）。假设你的 Employee 有个 hire_time 或者按默认顺序反转
			sorted_list.reverse() 
		SortType.TIME_ASC: # 正序
			pass # 默认就是正序
			
	return sorted_list
