extends Node

const SAVE_PATH = "user://savegame.json"

const EMPLOYEE_SCENE = preload("res://scenes/employee/employee.tscn")
const VISUAL_SCENES = {
	0: preload("res://scenes/employee/r_visual.tscn"),  
	1: preload("res://scenes/employee/sr_visual.tscn"), 
	2: preload("res://scenes/employee/ssr_visual.tscn") 
}

func _ready() -> void:
	pass

# ================= 一键删档 =================
func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
		print("存档已物理删除")
	
	Gamemanager.kpi = 10000
	Gamemanager.dollar = 10000
	Gamemanager.player_level = 1
	Gamemanager.total_hits = 0
	Gamemanager.total_time = 0.0
	
	if EmployeeManager.get("my_employees") != null:
		EmployeeManager.my_employees.clear()
		
	get_tree().reload_current_scene()

# ================= 存档核心逻辑 =================
func save_game() -> void:
	var save_data = {}
	
	save_data["player"] = {
		"level": Gamemanager.player_level,
		"kpi": Gamemanager.kpi,
		"dollar": Gamemanager.dollar,
		"total_hits": Gamemanager.total_hits,
		"total_time": Gamemanager.total_time
	}
	
	var offices_data = {}
	for office in get_tree().get_nodes_in_group("offices"):
		offices_data[office.name] = {
			"is_locked": office.is_locked,
			"current_type": office.current_type
		}
	save_data["offices"] = offices_data
	
	var employee_data = []
	for emp in EmployeeManager.my_employees:
		if is_instance_valid(emp):
			var emp_dict = {
				"employee_name": emp.employee_name,
				"rarity": emp.rarity,
				"efficiency": emp.efficiency,
				"quality": emp.quality,
				"experience": emp.experience,
				"dna": emp.dna, 
				"is_in_meeting": emp.is_in_meeting,
				"is_on_map": false, 
				"seat_path": "",
				"pos_x": 0.0,
				"pos_y": 0.0
			}
			
			if emp.get_parent() != null:
				emp_dict["is_on_map"] = true
				emp_dict["pos_x"] = emp.global_position.x
				emp_dict["pos_y"] = emp.global_position.y
				
				if emp.current_seat != null:
					emp_dict["seat_path"] = str(emp.current_seat.get_path())
					
			employee_data.append(emp_dict)
			
	save_data["employees"] = employee_data
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	print("[SaveSystem] 游戏保存成功！")

# ================= 延迟吸附辅助函数 =================
# 🌟 保险措施：等所有节点都加载完，再去找工位，防止报错
func _deferred_snap(emp: Employee, path: String) -> void:
	if not is_instance_valid(emp): return
	var seat = get_node_or_null(path)
	if seat != null:
		emp.snap_to_seat(seat, false)
	else:
		print("[SaveManager] 警告：找不到存档中的工位路径: ", path)

# ================= 读取员工转生版 =================
func _restore_employees(emp_list: Array) -> void:
	var container = get_tree().current_scene.find_child("EmployeeContainer", true, false)
	
	if EmployeeManager.get("my_employees") != null:
		for old_emp in EmployeeManager.my_employees:
			if is_instance_valid(old_emp):
				old_emp.queue_free()
		EmployeeManager.my_employees.clear()
		
	for e_data in emp_list:
		var new_emp = EMPLOYEE_SCENE.instantiate() as Employee
		
		# 数据转换
		var e_rarity = int(e_data.get("rarity", 0))
		new_emp.employee_name = e_data.get("employee_name", "Marry")
		new_emp.rarity = e_rarity as Employee.Rarity
		new_emp.efficiency = int(e_data.get("efficiency", 1))
		new_emp.quality = int(e_data.get("quality", 1))
		new_emp.experience = int(e_data.get("experience", 1))
		
		var raw_dna = e_data.get("dna", {})
		var clean_dna = {}
		for key in raw_dna:
			clean_dna[key] = int(raw_dna[key])
		new_emp.dna = clean_dna 
		
		# ========================================================
		# 🌟 修复点 1：把外表精准挂载到 VisualAnchor 节点下，对齐包围盒
		# ========================================================
		var visual_scene = VISUAL_SCENES.get(e_rarity)
		if visual_scene:
			var visual_instance = visual_scene.instantiate()
			
			var anchor = new_emp.get_node_or_null("VisualAnchor")
			if anchor:
				anchor.add_child(visual_instance)
			else:
				new_emp.add_child(visual_instance)
				
			new_emp.visual_component = visual_instance
			
			if visual_instance.has_method("setup_visual"):
				visual_instance.setup_visual(0, new_emp.dna, new_emp.rarity)
			
			if visual_instance.has_method("generate_portrait_texture"):
				new_emp.portrait = visual_instance.generate_portrait_texture()
		
		EmployeeManager.my_employees.append(new_emp)
		EmployeeManager.employee_added.emit(new_emp)

		var is_on_map = e_data.get("is_on_map", false)
		if is_on_map:
			# ========================================================
			# 🌟 修复点 2：强行唤醒所有碰撞和鼠标检测
			# ========================================================
			new_emp.visible = true
			new_emp.mouse_filter = Control.MOUSE_FILTER_STOP
			new_emp.process_mode = Node.PROCESS_MODE_INHERIT
			
			if container: 
				container.add_child.call_deferred(new_emp)
			else: 
				get_tree().current_scene.add_child.call_deferred(new_emp)
			
			var seat_path = e_data.get("seat_path", "")
			if seat_path != "":
				# 🌟 修复点 3：利用刚才写的辅助函数，安全延迟吸附工位
				Callable(self, "_deferred_snap").call_deferred(new_emp, seat_path)
			else:
				var pos_x = float(e_data.get("pos_x", 0.0))
				var pos_y = float(e_data.get("pos_y", 0.0))
				new_emp.set_deferred("global_position", Vector2(pos_x, pos_y))
				new_emp.add_to_group("dropped_employee")
		else:
			new_emp.visible = false
			new_emp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			new_emp.process_mode = Node.PROCESS_MODE_DISABLED
			
		if e_data.get("is_in_meeting", false):
			new_emp.call_deferred("enter_meeting")

# ================= 读取游戏基础逻辑 =================
func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
		
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var json_str = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_str) != OK: return
		
	var save_data = json.data
	
	if save_data.has("player"):
		var p_data = save_data["player"]
		Gamemanager.player_level = int(p_data.get("level", 1))
		Gamemanager.kpi = int(p_data.get("kpi", 10000))
		Gamemanager.dollar = int(p_data.get("dollar", 10000))
		Gamemanager.total_hits = int(p_data.get("total_hits", 0))
		Gamemanager.total_time = float(p_data.get("total_time", 0.0))
		
	if save_data.has("offices"):
		var o_data = save_data["offices"]
		for office in get_tree().get_nodes_in_group("offices"):
			if o_data.has(office.name):
				var single_o = o_data[office.name]
				office.is_locked = single_o.get("is_locked", true)
				var saved_type = int(single_o.get("current_type", Gamemanager.OfficeType.NONE))
				if not office.is_locked and saved_type != Gamemanager.OfficeType.NONE:
					office.change_function(saved_type)
					
	if save_data.has("employees"):
		_restore_employees(save_data["employees"])
		
	print("[SaveSystem] 游戏读取成功！")
