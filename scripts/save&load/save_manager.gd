extends Node

const SAVE_PATH = "user://savegame.json"

# 🌟 请在这里填写你场景中“存放员工”的父节点名字
# 建议在主场景里建一个叫 "EmployeeContainer" 的 Node2D
const EMPLOYEE_CONTAINER_PATH = "Main/EmployeeContainer" 
const EMPLOYEE_SCENE = preload("res://scenes/employee/employee.tscn")
const VISUAL_SCENES = {
	0: preload("res://scenes/employee/r_visual.tscn"),  # Rarity.R
	1: preload("res://scenes/employee/sr_visual.tscn"), # Rarity.SR
	2: preload("res://scenes/employee/ssr_visual.tscn") # Rarity.SSR
}
func _ready() -> void:
	# ... 原有的 timer 逻辑保持不变 ...
	pass

# ================= 一键删档 =================
# ================= 一键删档 =================
func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
		print("存档已物理删除")
	
	# 重置内存中的关键数据
	Gamemanager.kpi = 10000
	Gamemanager.dollar = 10000
	Gamemanager.player_level = 1
	
	# 🌟 修复 Bug 的核心所在：清空全局单例里残留的员工数据
	if EmployeeManager.get("my_employees") != null:
		EmployeeManager.my_employees.clear()
		
	# 如果你还有其他单例（比如 OfficeManager）里的状态需要重置，也可以写在这里
	# OfficeManager.has_recruitment_office = false
	# OfficeManager.has_culture_center = false
		
	# 强制重启当前场景以应用重置
	get_tree().reload_current_scene()

# ================= 存档修复版 =================
func save_game() -> void:
	# ... (省略基础数值保存代码，保持原样) ...
	
	var employee_data = []
	for emp in EmployeeManager.my_employees:
		if is_instance_valid(emp):
# ... 在保存员工信息的循环里 ...
			var emp_dict = {
				"employee_name": emp.employee_name,
				"rarity": emp.rarity,
				"efficiency": emp.efficiency,
				"quality": emp.quality,
				"experience": emp.experience,
				"is_in_meeting": emp.is_in_meeting,
				"dna": emp.dna,  # 🌟 直接把存好的基因打包！
				"seat_path": ""
			}
			# ... 下面不用动
			if emp.current_seat:
				emp_dict["seat_path"] = str(emp.current_seat.get_path())
			employee_data.append(emp_dict)
	print("[SaveSystem] 准备保存员工，当前管理器中的员工总数: ", EmployeeManager.my_employees.size())
	# ... (写入文件逻辑保持不变) ...

# ================= 读取修复版 =================
func _restore_employees(emp_list: Array) -> void:
	# 1. 寻找存放员工的容器（Main 场景里的 EmployeeContainer）
	var container = get_tree().root.find_child("EmployeeContainer", true, false)
	
	# 2. 清理当前场景中可能残留的旧员工节点和数据
	if EmployeeManager.get("my_employees") != null:
		for old_emp in EmployeeManager.my_employees:
			if is_instance_valid(old_emp):
				old_emp.queue_free()
		EmployeeManager.my_employees.clear()
		
	# 3. 开始遍历存档列表，逐一“转生”员工
	for e_data in emp_list:
		# 实例化通用的身体
		var new_emp = EMPLOYEE_SCENE.instantiate() as Employee
		
		# 还原基础属性和基因
		var e_rarity = e_data.get("rarity", 0)
		new_emp.employee_name = e_data.get("employee_name", "Marry")
		new_emp.rarity = e_rarity as Employee.Rarity
		new_emp.efficiency = e_data.get("efficiency", 1)
		new_emp.quality = e_data.get("quality", 1)
		new_emp.experience = e_data.get("experience", 1)
		new_emp.dna = e_data.get("dna", {}) # 注入保存的长相索引
		
		# 挂载视觉外衣 (R/SR/SSR)
		var visual_scene = VISUAL_SCENES.get(e_rarity)
		if visual_scene:
			var visual_instance = visual_scene.instantiate()
			new_emp.add_child(visual_instance)
			new_emp.visual_component = visual_instance
			
			# 传入基因生成对应的长相，不再随机
			if visual_instance.has_method("setup_visual"):
				visual_instance.setup_visual(0, new_emp.dna)
			
			# 重新生成简历头像
			if visual_instance.has_method("generate_portrait_texture"):
				new_emp.portrait = visual_instance.generate_portrait_texture()
		
		# 登记到管理器
		EmployeeManager.my_employees.append(new_emp)
		EmployeeManager.employee_added.emit(new_emp)

		# 4. 恢复位置（修复 Parent node is busy 报错的关键部分）
		var seat_path = e_data.get("seat_path", "")
		if seat_path != "":
			# 使用 call_deferred 确保在场景树空闲时添加节点，避免冲突
			if container: 
				container.add_child.call_deferred(new_emp)
			else: 
				get_tree().root.add_child.call_deferred(new_emp)
			
			# 必须同样延迟调用吸附函数，否则坐标计算会出错
			new_emp.call_deferred("snap_to_seat", get_node_or_null(seat_path), false)
		else:
			# 如果员工在仓库里，不需要调用 add_child 放到地图上
			pass 
			
		# 5. 恢复会议状态
		if e_data.get("is_in_meeting", false):
			new_emp.call_deferred("enter_meeting")

# ================= 读取游戏基础逻辑 =================
func load_game() -> void:
	# 1. 检查有没有存档文件，没有就直接 return 当无事发生
	if not FileAccess.file_exists(SAVE_PATH):
		return
		
	# 2. 读取文件并解析 JSON
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var json_str = file.get_as_text()
	file.close()
	
	
	var json = JSON.new()
	if json.parse(json_str) != OK:
		print("存档文件解析失败或损坏")
		return
		
	var save_data = json.data
	
	# 3. 恢复全局数值 (KPI、美金、等级等)
	if save_data.has("player"):
		var p_data = save_data["player"]
		Gamemanager.player_level = p_data.get("level", 1)
		Gamemanager.kpi = p_data.get("kpi", 0)
		Gamemanager.dollar = p_data.get("dollar", 0)
		Gamemanager.total_hits = p_data.get("total_hits", 0)
		Gamemanager.total_time = p_data.get("total_time", 0.0)
		
	# 4. 恢复办公室解锁状态和建造的功能
	if save_data.has("offices"):
		var o_data = save_data["offices"]
		for office in get_tree().get_nodes_in_group("offices"):
			if o_data.has(office.name):
				var single_o = o_data[office.name]
				office.is_locked = single_o.get("is_locked", true)
				var saved_type = single_o.get("current_type", Gamemanager.OfficeType.NONE)
				if not office.is_locked and saved_type != Gamemanager.OfficeType.NONE:
					office.change_function(saved_type)
					
	# 5. 把存档里的员工列表传给我们刚才写好的核心转生函数
	if save_data.has("employees"):
		_restore_employees(save_data["employees"])
		
