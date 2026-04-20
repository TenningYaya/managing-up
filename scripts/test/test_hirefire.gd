# test_hirefire.gd
extends Node

# 测试节点只需要简单的导出变量连到按钮上
func _on_test_normal_gen_pressed():
	RecruitmentManager.auto_generate_normal()

func _on_clear_all_test():
	print("【测试】开始执行大清洗...")
	
	# 1. 先把主列表复制一份，防止循环崩溃
	var all_staff = EmployeeManager.my_employees.duplicate()
	
	# 2. 彻底清理地图上的所有“实体”小人
	# 哪怕名字对不上，只要是这个组的，全删掉，防止残留
	var dropped_nodes = get_tree().get_nodes_in_group("dropped_employee")
	for node in dropped_nodes:
		node.queue_free()
	
	# 3. 遍历数据并销毁
	for emp in all_staff:
		# 清理工位
		if emp.current_seat != null:
			emp.current_seat.clear_occupant()
			emp.current_seat = null
			
		# 发送信号（让仓库尝试自己刷一遍）
		EmployeeManager.employee_removed.emit(emp)
		EmployeeManager.my_employees.erase(emp)
		
		# 彻底毁尸灭迹
		if is_instance_valid(emp):
			emp.queue_free()

	# 4. 【关键新增】：强制清理仓库的 UI 网格
	# 这样哪怕信号没处理好，物理上的名片也必须消失
	var warehouse = get_tree().get_first_node_in_group("employee_warehouse")
	if warehouse:
		# 假设你的仓库里存放名片的节点叫 grid (GridContainer)
		# 我们直接调用你写好的 refresh_display 
		# 或者暴力清理 grid 的子节点
		warehouse.refresh_display() 
	
	print("【测试】全员已优化，UI 已强制刷新。")

func _on_normal_10_pressed() -> void:
	# 1. 跑 10 次循环
	for i in range(10):
		# 注意：这里我们调用原本写好的单次生成逻辑
		RecruitmentManager.auto_generate_normal()
