extends Node

const SAVE_PATH = "user://savegame.json"

# 🌟 缓存读档时解析出的办公室数据，供办公室节点在自己的 _ready 里自愈取用。
# 解决“load_game 与办公室 _ready 谁先谁后”的时序问题。
var _loaded_office_data: Dictionary = {}

const EMPLOYEE_SCENE = preload("res://scenes/employee/employee.tscn")
const VISUAL_SCENES = {
	0: preload("res://scenes/employee/sr_visual.tscn"),  
}

func _ready() -> void:
	pass

# ================= 一键删档 =================
func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
		print("存档已物理删除")
	
	Gamemanager.kpi = 2000
	Gamemanager.dollar = 100
	Gamemanager.player_level = 1
	Gamemanager.total_hits = 0
	Gamemanager.total_time = 0.0
	Gamemanager.max_desk_level = 1
	Gamemanager.unlocked_desk_slots = 1
	
	# 🌟 关键：把教程标志位也归 0，否则重载场景后 tutorial_layer._ready()
	#    会因为 is_tutorial_completed 仍为 true 而 queue_free 自己，导致教程不重播。
	Gamemanager.is_tutorial_completed = false
	# 🌟 顺手复位教程期间会被打开的两个交互总闸，防止在教程进行中删档时残留禁用状态。
	Gamemanager.is_employee_interaction_disabled = false
	Gamemanager.is_reject_button_disabled = false

	# 🌟 普通招募免费简历计时器也要清零：RecruitmentManager 是 autoload，不随场景重载复位，
	#    不手动归零的话删档重开会沿用上一局的剩余时间与已出现数量。
	RecruitmentManager.free_recruit_count = 0
	RecruitmentManager.free_recruit_time_left = RecruitmentManager.FREE_RECRUIT_INTERVAL_EARLY

	if EmployeeManager.get("my_employees") != null:
		EmployeeManager.my_employees.clear()
	
	# 🌟 清空办公室存档缓存，否则开新档后办公室 _ready 会误用上一局的解锁记录
	_loaded_office_data.clear()
		
	get_tree().reload_current_scene()

# ================= 存档核心逻辑 =================
func save_game() -> void:
	var save_data = {}
	save_data["is_tutorial_completed"] = Gamemanager.is_tutorial_completed	
	save_data["player"] = {
		"level": Gamemanager.player_level,
		"kpi": Gamemanager.kpi,
		"dollar": Gamemanager.dollar,
		"total_hits": Gamemanager.total_hits,
		"total_time": Gamemanager.total_time,
		"max_desk_level": Gamemanager.max_desk_level,
		"unlocked_desk_slots": Gamemanager.unlocked_desk_slots
	}
	
	var offices_data = {}
	for office in get_tree().get_nodes_in_group("offices"):
		offices_data[office.name] = {
			"is_locked": office.is_locked,
			"current_type": office.current_type
		}
	save_data["offices"] = offices_data
	
	var desk_slots_data = {}
	for slot in get_tree().get_nodes_in_group("desk_slots"):
		desk_slots_data[slot.name] = slot.slot_level
	save_data["desk_slots"] = desk_slots_data
	
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
	
	# ================= 🌟 招聘池存档（尚未决定录用/拒绝的简历）=================
	save_data["recruitment"] = {
		"current_state": RecruitmentManager.current_state,
		"headhunt_time_left": RecruitmentManager.headhunt_time_left,
		"pending_amount": RecruitmentManager._pending_amount,
		"free_recruit_count": RecruitmentManager.free_recruit_count,
		"free_recruit_time_left": RecruitmentManager.free_recruit_time_left,
		"normal_pool": _serialize_resume_pool(RecruitmentManager.normal_pool),
		"headhunt_pool": _serialize_resume_pool(RecruitmentManager.headhunt_pool),
	}
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	print("[SaveSystem] Is Toturial completed: ", save_data["is_tutorial_completed"])

# 🌟 把一个招聘池（normal_pool / headhunt_pool）里的简历转成可存档的字典数组
func _serialize_resume_pool(pool: Array) -> Array:
	var arr = []
	for emp in pool:
		if is_instance_valid(emp):
			arr.append({
				"employee_name": emp.employee_name,
				"rarity": emp.rarity,
				"efficiency": emp.efficiency,
				"quality": emp.quality,
				"experience": emp.experience,
				"dna": emp.dna,
				"is_headhunt": emp.is_headhunt,
			})
	return arr

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
# 🌟 从存档字典造出一个 Employee 实例（含外观与头像），但不挂进场景树、不做地图摆放。
#    入职员工和招聘池简历都用它来重建。
func _instantiate_employee_from_dict(e_data: Dictionary) -> Employee:
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
	
	# 🌟 把外表精准挂载到 VisualAnchor 节点下，对齐包围盒
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
	
	return new_emp

func _restore_employees(emp_list: Array) -> void:
	var container = get_tree().current_scene.find_child("EmployeeContainer", true, false)
	
	if EmployeeManager.get("my_employees") != null:
		for old_emp in EmployeeManager.my_employees:
			if is_instance_valid(old_emp):
				old_emp.queue_free()
		EmployeeManager.my_employees.clear()
		
	for e_data in emp_list:
		var new_emp = _instantiate_employee_from_dict(e_data)
		
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

# ================= 办公室存档恢复 =================
# 🌟 提供给办公室节点查询自己的存档状态（按节点名）
func get_saved_office_state(office_name: String) -> Dictionary:
	if _loaded_office_data.has(office_name):
		return _loaded_office_data[office_name]
	return {}

# 🌟 统一恢复当前已在场景里的办公室。
# 语义：只解锁、不回锁，永远不会因为读档把已解锁的办公室锁回去。
func _restore_offices() -> void:
	for office in get_tree().get_nodes_in_group("offices"):
		if not _loaded_office_data.has(office.name):
			continue
		var single_o = _loaded_office_data[office.name]
		if not bool(single_o.get("is_locked", true)):
			office.is_locked = false
		var saved_type = int(single_o.get("current_type", Gamemanager.OfficeType.NONE))
		if not office.is_locked and saved_type != Gamemanager.OfficeType.NONE:
			office.change_function(saved_type)

# ================= 🌟 招聘池恢复 =================
func _restore_recruitment(rec_data: Dictionary) -> void:
	# 1. 先释放旧的招聘池实例，防止内存泄漏
	for old in RecruitmentManager.normal_pool:
		if is_instance_valid(old):
			old.queue_free()
	for old in RecruitmentManager.headhunt_pool:
		if is_instance_valid(old):
			old.queue_free()
	
	# 2. 🌟 关键：原地清空再填充，绝不能写成 RecruitmentManager.normal_pool = 新数组！
	#    因为 recruitment_panel.gd 在 _ready 里 bind 的是这个数组的“引用”，
	#    一旦换成新数组对象，面板的录用/拒绝就会操作到旧数组，导致同步错乱。
	RecruitmentManager.normal_pool.clear()
	for e_data in rec_data.get("normal_pool", []):
		var emp = _instantiate_employee_from_dict(e_data)
		emp.is_headhunt = bool(e_data.get("is_headhunt", false))
		RecruitmentManager.normal_pool.append(emp)
	
	RecruitmentManager.headhunt_pool.clear()
	for e_data in rec_data.get("headhunt_pool", []):
		var emp = _instantiate_employee_from_dict(e_data)
		emp.is_headhunt = bool(e_data.get("is_headhunt", true))
		RecruitmentManager.headhunt_pool.append(emp)
	
	# 3. 恢复招聘状态。倒计时由 RecruitmentManager._process 驱动，
	#    所以只要把这三个值设回去，读档后倒计时会自动接着走、结束时也能正确生成猎头简历。
	RecruitmentManager.current_state = int(rec_data.get("current_state", 0))
	RecruitmentManager.headhunt_time_left = float(rec_data.get("headhunt_time_left", 0.0))
	RecruitmentManager._pending_amount = int(rec_data.get("pending_amount", 0))

	# 普通招募免费简历计时器（已出现数量 & 剩余时间）。旧存档没有这两项时按全新计时处理。
	RecruitmentManager.free_recruit_count = int(rec_data.get("free_recruit_count", 0))
	RecruitmentManager.free_recruit_time_left = float(rec_data.get("free_recruit_time_left", RecruitmentManager.FREE_RECRUIT_INTERVAL_EARLY))
	
	# 4. 通知面板刷新（如果此刻面板已打开）
	if RecruitmentManager.has_signal("new_resumes_arrived"):
		RecruitmentManager.new_resumes_arrived.emit()

# ================= 读取游戏基础逻辑 =================
func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
		
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var json_str = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_str) != OK: return
		
	var save_data = json.data
	if save_data.has("is_tutorial_completed"):
		Gamemanager.is_tutorial_completed = save_data["is_tutorial_completed"]
		
	if save_data.has("player"):
		var p_data = save_data["player"]
		Gamemanager.player_level = int(p_data.get("level", 1))
		Gamemanager.kpi = int(p_data.get("kpi", 10000))
		Gamemanager.dollar = int(p_data.get("dollar", 10000))
		Gamemanager.total_hits = int(p_data.get("total_hits", 0))
		Gamemanager.total_time = float(p_data.get("total_time", 0.0))
		Gamemanager.max_desk_level = int(p_data.get("max_desk_level", 1))
		Gamemanager.unlocked_desk_slots = int(p_data.get("unlocked_desk_slots", 1))
		
	if save_data.has("offices"):
		# 缓存起来：晚于 load_game 才 _ready 的办公室会自己来取（自愈）
		_loaded_office_data = save_data["offices"]
		# 当前已经在场景里的办公室，立刻恢复
		_restore_offices()
					
	if save_data.has("desk_slots"):
		var d_data = save_data["desk_slots"]
		for slot in get_tree().get_nodes_in_group("desk_slots"):
			if d_data.has(slot.name):
				var loaded_level = int(d_data[slot.name])
				slot.slot_level = loaded_level
				for desk in slot.grid_container.get_children():
					if desk is DeskSeat: 
						desk.set_upgrade_level(loaded_level)
						
	if save_data.has("employees"):
		_restore_employees(save_data["employees"])
	
	if save_data.has("recruitment"):
		_restore_recruitment(save_data["recruitment"])
	
	print("[SaveSystem] 游戏读取成功！")
