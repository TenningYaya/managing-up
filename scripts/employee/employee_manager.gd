# employee_manager.gd
extends Node

# ==========================================
# 信号 (Signals)：发生变化时通知全服
# ==========================================
signal employee_added(employee_data: Employee)
signal employee_removed(employee_data: Employee)
signal employee_map_status_changed
# ==========================================
# 核心数据 (Data)
# ==========================================
var my_employees: Array[Employee] = [] # 玩家拥有的所有员工列表
enum SortType { SUM_DESC, SUM_ASC, TIME_DESC, TIME_ASC }
var _pending_banter_emps: Array[Employee] = [] # 🌟 新增：等待吐槽的“缓冲篮子”
# ==========================================
# 员工名册管理API (管人)
# ==========================================
# 录用新员工 (现在兼顾单抽和十连抽)
func hire_employee(new_employee: Employee) -> void:
	if new_employee not in my_employees:
		my_employees.append(new_employee)
		employee_added.emit(new_employee) # 通知仓库去生成UI名片
		
		# 🌟 1. 进来一个员工，就扔进缓冲篮子
		_pending_banter_emps.append(new_employee)
		
		# 🌟 2. 只有当篮子里是第 1 个人时，才启动计时器！
		# 这样一瞬间塞进来的第 2、3、4、5 个人，只会进篮子，不会再开额外的计时器了！
		if _pending_banter_emps.size() == 1:
			get_tree().create_timer(0.5).timeout.connect(_process_banter_queue)

# 🌟 计时器到了，清空篮子并统一结算
func _process_banter_queue() -> void:
	if _pending_banter_emps.is_empty(): return
	
	# 把篮子里的人打包拿出来
	var batch_to_process = _pending_banter_emps.duplicate()
	_pending_banter_emps.clear() # 清空篮子，等下一波招聘
	
	# 移交给吐槽结算中心
	_trigger_hiring_banters(batch_to_process)
	
func fire_employee(employee: Employee) -> void:
	if employee in my_employees:
		my_employees.erase(employee)
		employee_removed.emit(employee)
		# 如果他还在座位上，记得让他腾出座位 (调用之前写的 clear_occupant)
		if employee.current_seat != null:
			employee.current_seat.clear_occupant()
		
		# 释放节点内存
		employee.queue_free() 

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

# ==========================================
# 🌟 统一的闲聊结算中心
# ==========================================
func _trigger_hiring_banters(hired_list: Array) -> void:
	# ----------------------------------------
	# 需求 1：招谁谁吐槽（新人自己抱怨），最多随机 3 个
	# ----------------------------------------
	var speaking_count = min(hired_list.size(), 3)
	
	var shuffled_list = hired_list.duplicate()
	shuffled_list.shuffle() 
	
	for i in range(speaking_count):
		var new_guy = shuffled_list[i]
		
		if is_instance_valid(new_guy) and new_guy.has_method("play_on_hired_banter"):
			# 🌟 核心魔法：每个人生成一个独立的 0.0 到 3.0 秒之间的随机延迟
			var random_delay = randf_range(0.0, 3.0)
			
			# 🌟 开启异步倒计时，时间到了再让他们开口，绝不卡死游戏主线程
			get_tree().create_timer(random_delay).timeout.connect(func():
				# 🚨【生死锁防御】：因为延迟最高有 3 秒，防止这期间玩家神速把刚招的人给“解雇”了
				if is_instance_valid(new_guy) and new_guy.has_method("play_on_hired_banter"):
					new_guy.play_on_hired_banter()
			)

	# ----------------------------------------
	# 需求 2：SSR 空降引发老员工围观 (保持你之前的代码不变)
	# ----------------------------------------
	var has_ssr = false
	for emp in hired_list:
		if emp.rarity == Employee.Rarity.SSR:
			has_ssr = true
			break
			
	if has_ssr:
		# 🌟 顺手把老员工的围观也往后稍稍，等新人开始吐槽了，老员工再惊呼，层次感更好
		get_tree().create_timer(1.0).timeout.connect(func():
			BanterManager.trigger_banter("hired_ssr", 3)
		)
