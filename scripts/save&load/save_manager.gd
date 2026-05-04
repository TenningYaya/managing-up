extends Node

const SAVE_PATH = "user://savegame.json"
const EMPLOYEE_SCENE_PATH = "res://scenes/employee.tscn" # 请根据实际的员工场景路径进行修改

var save_timer: Timer

func _ready() -> void:
	# 配置自动存档定时器，每60秒在后台静默保存一次
	save_timer = Timer.new()
	save_timer.wait_time = 60.0 
	save_timer.autostart = true
	save_timer.timeout.connect(save_game)
	add_child(save_timer)

func save_game() -> void:
	var save_data = {}
	
	# 记录当前Unix时间戳，用于计算离线收益
	save_data["timestamp"] = Time.get_unix_time_from_system()
	
	# 提取全局基础数值
	save_data["player"] = {
		"level": Gamemanager.player_level,
		"kpi": Gamemanager.kpi,
		"dollar": Gamemanager.dollar,
		"total_hits": Gamemanager.total_hits,
		"total_time": Gamemanager.total_time
	}
	
	# 遍历并保存所有办公室节点的状态
	var office_data = {}
	for office in get_tree().get_nodes_in_group("offices"):
		office_data[office.name] = {
			"is_locked": office.is_locked,
			"current_type": office.current_type
		}
	save_data["offices"] = office_data
	
	# 遍历并保存所有员工的属性及位置状态
	var employee_data = []
	if EmployeeManager.get("my_employees") != null:
		for emp in EmployeeManager.my_employees:
			if not is_instance_valid(emp):
				continue
				
			var emp_dict = {
				"employee_name": emp.employee_name,
				"rarity": emp.rarity,
				"efficiency": emp.efficiency,
				"quality": emp.quality,
				"experience": emp.experience,
				"is_in_meeting": emp.is_in_meeting,
				"seat_path": ""
			}
			
			# 如果员工当前在工位上，记录工位节点的绝对路径
			if emp.current_seat != null and is_instance_valid(emp.current_seat):
				emp_dict["seat_path"] = str(emp.current_seat.get_path())
				
			employee_data.append(emp_dict)
			
	save_data["employees"] = employee_data
	
	# 转换为JSON并写入本地文件
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))
		file.close()
		print("游戏状态已自动保存至本地")

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
		
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var json_str = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_str) != OK:
		print("存档文件解析失败或损坏")
		return
		
	var save_data = json.data
	
	# 恢复全局数值
	if save_data.has("player"):
		var p_data = save_data["player"]
		Gamemanager.player_level = p_data.get("level", 1)
		Gamemanager.kpi = p_data.get("kpi", 0)
		Gamemanager.dollar = p_data.get("dollar", 0)
		Gamemanager.total_hits = p_data.get("total_hits", 0)
		Gamemanager.total_time = p_data.get("total_time", 0.0)
		
	# 恢复办公室状态
	if save_data.has("offices"):
		var o_data = save_data["offices"]
		for office in get_tree().get_nodes_in_group("offices"):
			if o_data.has(office.name):
				var single_o = o_data[office.name]
				office.is_locked = single_o.get("is_locked", true)
				var saved_type = single_o.get("current_type", Gamemanager.OfficeType.NONE)
				if not office.is_locked and saved_type != Gamemanager.OfficeType.NONE:
					office.change_function(saved_type)
					
	# 恢复员工数据并重新分配工位
	if save_data.has("employees"):
		_restore_employees(save_data["employees"])
		
	# 结算离线挂机收益
	if save_data.has("timestamp"):
		_calculate_offline_earnings(save_data["timestamp"])

func _restore_employees(emp_list: Array) -> void:
	var emp_scene = load(EMPLOYEE_SCENE_PATH)
	
	# 清理当前可能存在的初始员工数据
	if EmployeeManager.get("my_employees") != null:
		for old_emp in EmployeeManager.my_employees:
			if is_instance_valid(old_emp):
				old_emp.queue_free()
		EmployeeManager.my_employees.clear()
		
	for e_data in emp_list:
		var new_emp = emp_scene.instantiate()
		
		# 还原基础属性
		new_emp.employee_name = e_data.get("employee_name", "Marry")
		new_emp.rarity = e_data.get("rarity", 0)
		new_emp.efficiency = e_data.get("efficiency", 1)
		new_emp.quality = e_data.get("quality", 1)
		new_emp.experience = e_data.get("experience", 1)
		
		EmployeeManager.my_employees.append(new_emp)
		EmployeeManager.employee_added.emit(new_emp)
		
		# 尝试还原物理位置与状态
		var seat_path = e_data.get("seat_path", "")
		if seat_path != "":
			var seat_node = get_node_or_null(seat_path)
			if seat_node:
				# 将员工添加进场景树并吸附到读取到的工位上
				get_tree().root.add_child(new_emp)
				new_emp.snap_to_seat(seat_node, false)
				
		# 如果离开前被拖进了会议室，强制恢复开会状态
		if e_data.get("is_in_meeting", false):
			new_emp.enter_meeting()

func _calculate_offline_earnings(last_time: float) -> void:
	var current_time = Time.get_unix_time_from_system()
	var offline_seconds = current_time - last_time
	
	if offline_seconds <= 0:
		return
		
	var offline_kpi = 0
	if EmployeeManager.get("my_employees") != null:
		for emp in EmployeeManager.my_employees:
			# 只有正在工作或开会的员工才能产出离线收益
			if is_instance_valid(emp) and emp.is_working:
				var cycle_time = maxf(2.0, emp.current_cycle_duration)
				var files_produced = offline_seconds / cycle_time
				var base_value = emp.base_kpi_value
				offline_kpi += int(files_produced * base_value)
				
	if offline_kpi > 0:
		Gamemanager.add_kpi(offline_kpi)
		print("离线挂机收益结算完成，经过时间: ", int(offline_seconds), " 秒，总计获得 KPI: ", offline_kpi)

func _notification(what: int) -> void:
	# 拦截游戏窗口关闭请求，强制执行一次终局保存
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
		get_tree().quit()
