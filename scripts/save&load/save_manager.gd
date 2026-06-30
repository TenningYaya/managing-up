extends Node

const SAVE_PATH = "user://savegame.json"

# ===== 自动存档 =====
const AUTOSAVE_INTERVAL := 60.0       # 每 60 秒自动存一次
const AUTOSAVE_MIN_GAP_MS := 5000     # 两次自动存档至少隔 5 秒(防止失焦时被狂触发)
var _autosave_timer: Timer = null
var _last_autosave_msec: int = 0

# 🌟 缓存读档时解析出的办公室数据，供办公室节点在自己的 _ready 里自愈取用。
# 解决“load_game 与办公室 _ready 谁先谁后”的时序问题。
var _loaded_office_data: Dictionary = {}

const EMPLOYEE_SCENE = preload("res://scenes/employee/employee.tscn")
const VISUAL_SCENES = {
	0: preload("res://scenes/employee/sr_visual.tscn"),  
}



func _ready() -> void:
	# 自动存档定时器:每 AUTOSAVE_INTERVAL 秒触发一次
	# (只有教程完成后才真正写盘,判断在 autosave() 里)
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = AUTOSAVE_INTERVAL
	_autosave_timer.one_shot = false
	_autosave_timer.autostart = true
	_autosave_timer.timeout.connect(autosave)
	add_child(_autosave_timer)

# 自动存档:仅教程完成后存 + 节流(防止失焦时被狂触发)。
# 定时器、切走失焦都调它;关窗口走 save_game() 强制存。
func autosave() -> void:
	if not Gamemanager.is_tutorial_completed:
		return
	var now := Time.get_ticks_msec()
	if now - _last_autosave_msec < AUTOSAVE_MIN_GAP_MS:
		return
	_last_autosave_msec = now
	save_game()

# ================= 一键删档 =================
func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
		print("存档已物理删除")
	# 顺手清掉原子写入可能残留的临时文件(正常 rename 成功后不会有,以防万一)
	if FileAccess.file_exists(SAVE_PATH + ".tmp"):
		DirAccess.remove_absolute(SAVE_PATH + ".tmp")

	Gamemanager.kpi = 2000
	Gamemanager.dollar = 100
	Gamemanager.player_level = 1
	Gamemanager.total_hits = 0
	Gamemanager.total_time = 0.0
	Gamemanager.total_speedups = 0
	Gamemanager.max_desk_level = 1
	Gamemanager.unlocked_desk_slots = 1
	
	# 🌟 关键：把教程标志位也归 0，否则重载场景后 tutorial_layer._ready()
	#    会因为 is_tutorial_completed 仍为 true 而 queue_free 自己，导致教程不重播。
	Gamemanager.is_tutorial_completed = false
	# 🌟 顺手复位教程期间会被打开的两个交互总闸，防止在教程进行中删档时残留禁用状态。
	Gamemanager.is_employee_interaction_disabled = false
	Gamemanager.is_reject_button_disabled = false
	Gamemanager.project_name = "NewProject"
	Gamemanager.player_avatar_index = 0
	Gamemanager.player_avatar_texture = preload("res://assets/tutorial/avatars/player_avatar_1.png")
	# 🌟 必须复位:否则重开教程会沿用上一局的"已选头像",导致选头像前点员工就冒气泡
	Gamemanager.has_selected_avatar = false
	# 删档时清掉上一局上传的自定义头像(状态复位 + 删掉落地文件)
	Gamemanager.player_avatar_is_custom = false
	if FileAccess.file_exists("user://player_avatar.png"):
		DirAccess.remove_absolute("user://player_avatar.png")
	FloorManager.change_all_floors(0, Vector2i(0, 8))  # 换成你的默认地板坐标

	# 🌟 RecruitmentManager 是 autoload，不随场景重载复位。必须整体复位，否则删档重开会
	#    沿用上一局的免费简历计时,以及残留的猎头"招募中"状态 → 还没出教程就在倒计时。
	RecruitmentManager.reset_to_default()

	if EmployeeManager.get("my_employees") != null:
		EmployeeManager.my_employees.clear()
		
	SpeedupQuoteSave.reset_to_default()
	Gamemanager.sticky_note_text = ""
	# 🌟 炒股系统复位:价格回中枢、持仓清零、补货/计时归零(StockManager 是 autoload,不复位会沿用上一局)
	StockManager.reset_to_default()
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
		"total_speedups": Gamemanager.total_speedups,
		"max_desk_level": Gamemanager.max_desk_level,
		"unlocked_desk_slots": Gamemanager.unlocked_desk_slots,
		"project_name": Gamemanager.project_name,
		"player_avatar_index": Gamemanager.player_avatar_index,
		"player_avatar_path": Gamemanager.player_avatar_texture.resource_path if Gamemanager.player_avatar_texture else "",
		"player_avatar_is_custom": Gamemanager.player_avatar_is_custom
	}
	
	var floor_data = FloorManager.get_current_floor_data()
	save_data["floor"] = {
		"source_id": floor_data.get("source_id", 0),
		"atlas_coords_x": floor_data.get("atlas_coords", Vector2i.ZERO).x,
		"atlas_coords_y": floor_data.get("atlas_coords", Vector2i.ZERO).y,
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
				"name_index": emp.name_index,
				"is_custom_named": emp.is_custom_named,
				"hire_time": emp.hire_time,
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
		"free_recruit_time_left": maxf(RecruitmentManager.free_recruit_time_left, 1.0),
		"normal_pool": _serialize_resume_pool(RecruitmentManager.normal_pool),
		"headhunt_pool": _serialize_resume_pool(RecruitmentManager.headhunt_pool),
	}
	
	# ================= 🌟 自定义催促台词存档 =================
	save_data["boss_quotes"] = SpeedupQuoteSave.boss_quotes

	save_data["sticky_note_text"] = Gamemanager.sticky_note_text

	# ================= 🌟 炒股系统存档(各股价格/持仓/成本/补货周期/计时) =================
	save_data["stock"] = StockManager.to_save_dict()

	# 🌟 原子写入:先写临时文件,成功后再改名覆盖正式存档。
	#    这样即使正好在写盘那一瞬间崩溃/断电,坏掉的也只是临时文件,真存档不会被写成半截。
	var tmp_path: String = SAVE_PATH + ".tmp"
	var file = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("[SaveSystem] 无法写入临时存档,本次保存跳过")
		return
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	var rerr := DirAccess.rename_absolute(tmp_path, SAVE_PATH)
	if rerr != OK:
		push_error("[SaveSystem] 存档改名失败,错误码: %d" % rerr)

# 🌟 把一个招聘池（normal_pool / headhunt_pool）里的简历转成可存档的字典数组
func _serialize_resume_pool(pool: Array) -> Array:
	var arr = []
	for emp in pool:
		if is_instance_valid(emp):
			arr.append({
				"employee_name": emp.employee_name,
				"name_index": emp.name_index,
				"hire_time": emp.hire_time,
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
	new_emp.name_index = int(e_data.get("name_index", -1))
	new_emp.is_custom_named = bool(e_data.get("is_custom_named", false))   # 老存档没有此项默认 false
	new_emp.hire_time = float(e_data.get("hire_time", -1.0))   # 在树前设好，_ready 才不会把它当新入职重置
	new_emp.refresh_name()   # 有 name_index 就按当前语言解析；老存档没有则保留 employee_name
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
	# ⚠️ VISUAL_SCENES 只登记了键 0，但所有稀有度其实共用 sr_visual（同 recruitment_manager）。
	#    SR/SSR(rarity 1/2) 必须回退到键 0，否则读档后非 R 员工没有视觉/头像（座位透明人）。
	var visual_scene = VISUAL_SCENES.get(e_rarity, VISUAL_SCENES.get(0))
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
	print("【存档】load_game 被调用")
	if not FileAccess.file_exists(SAVE_PATH): return
		
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var json_str = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_str) != OK: return
		
	var save_data = json.data
	Gamemanager.is_loading_save = true   # 读档期间设置等级等值会触发信号,但不该播升级特效
	if save_data.has("is_tutorial_completed"):
		Gamemanager.is_tutorial_completed = save_data["is_tutorial_completed"]
		
	if save_data.has("player"):
		var p_data = save_data["player"]
		Gamemanager.player_level = int(p_data.get("level", 1))
		Gamemanager.kpi = int(p_data.get("kpi", 10000))
		Gamemanager.dollar = int(p_data.get("dollar", 10000))
		Gamemanager.total_hits = int(p_data.get("total_hits", 0))
		Gamemanager.total_time = float(p_data.get("total_time", 0.0))
		Gamemanager.total_speedups = int(p_data.get("total_speedups", 0))
		Gamemanager.max_desk_level = int(p_data.get("max_desk_level", 1))
		Gamemanager.unlocked_desk_slots = int(p_data.get("unlocked_desk_slots", 1))
		Gamemanager.project_name = p_data.get("project_name", "NewProject")
		Gamemanager.player_avatar_index = int(p_data.get("player_avatar_index", 0))
		Gamemanager.player_avatar_is_custom = bool(p_data.get("player_avatar_is_custom", false))
		if Gamemanager.player_avatar_is_custom:
			# 自定义头像:从用户目录读固定文件;读不到(换机/文件丢失)就退回默认头像
			var custom_img := Image.new()
			if custom_img.load("user://player_avatar.png") == OK:
				Gamemanager.player_avatar_texture = ImageTexture.create_from_image(custom_img)
				Gamemanager.has_selected_avatar = true
			else:
				Gamemanager.player_avatar_is_custom = false
				Gamemanager.player_avatar_index = 0
				Gamemanager.player_avatar_texture = preload("res://assets/tutorial/avatars/player_avatar_1.png")
		else:
			var avatar_path = p_data.get("player_avatar_path", "")
			if avatar_path != "":
				Gamemanager.player_avatar_texture = load(avatar_path)
				Gamemanager.has_selected_avatar = true
	
	if save_data.has("floor"):
		var f_data = save_data["floor"]
		var coords = Vector2i(int(f_data.get("atlas_coords_x", 0)), int(f_data.get("atlas_coords_y", 8)))
		FloorManager.change_all_floors(int(f_data.get("source_id", 0)), coords)
	
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
	# ================= 🌟 自定义催促台词恢复 =================
	if save_data.has("boss_quotes"):
		# 确保读出来的是个数组
		if typeof(save_data["boss_quotes"]) == TYPE_ARRAY:
			# 复制一份覆盖当前内存
			SpeedupQuoteSave.boss_quotes = save_data["boss_quotes"].duplicate()

	if save_data.has("sticky_note_text"):
		Gamemanager.sticky_note_text = str(save_data["sticky_note_text"])

	# ================= 🌟 炒股系统恢复 =================
	if save_data.has("stock"):
		StockManager.load_from_dict(save_data["stock"])

	Gamemanager.is_loading_save = false
