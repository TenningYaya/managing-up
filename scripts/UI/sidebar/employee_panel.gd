#employee_panel.gd
extends Control
class_name EmployeePanel

# ==========================================
# 1. 节点引用 (严格对应截图层级)
# ==========================================
# --- 员工信息部分 ---
@onready var figure: TextureRect = $PanelBg/EmployeePage/NameCard/Figure
@onready var name_label: Label = $PanelBg/EmployeePage/NameCard/VBoxContainer/NameLabel
@onready var rarity_label: Label = $PanelBg/EmployeePage/NameCard/VBoxContainer/RarityLabel

# --- 属性条组件部分 ---
@onready var efficiency_bar: EmployeeAbility = $PanelBg/EmployeePage/Information/Abilities/EfficiencyBar
@onready var quality_bar: EmployeeAbility = $PanelBg/EmployeePage/Information/Abilities/QualityBar
@onready var experience_bar: EmployeeAbility = $PanelBg/EmployeePage/Information/Abilities/ExperienceBar

@onready var progress_bar: TextureProgressBar = $PanelBg/EmployeePage/Information/ProgressBar

# --- 底部按钮部分 ---
@onready var dispatch_btn: TextureButton = $PanelBg/EmployeePage/Manage/DispatchButton
@onready var fire_btn: TextureButton = $PanelBg/EmployeePage/Manage/NormalButton2 # 建议之后重命名为 FireButton
@onready var dispatch_btn_label: Label = $PanelBg/EmployeePage/Manage/DispatchButton/Label

# --- 弹窗部分 ---
@onready var popup_window = $PanelBg/PopupWindow

# 当前正在查看的员工数据引用
var current_employee: Employee = null

# --- buff部分 ---
@onready var buffs_container: Container = $PanelBg/EmployeePage/Information/Buffs
# ==========================================
# 2. 初始化
# ==========================================
func _ready() -> void:
	hide() 
	popup_window.hide()
	
	progress_bar.min_value = 0
	progress_bar.max_value = 100
	progress_bar.value = 0
	
	# 绑定底部按钮事件
	dispatch_btn.pressed.connect(_on_dispatch_pressed)
	fire_btn.pressed.connect(_on_fire_pressed)
	# ------------------------------------------
	# 3. 这里是连接 PopupWindow 的地方！
	# ------------------------------------------
	# 当 PopupWindow 发出 confirmed 信号时，执行开除逻辑
	popup_window.confirmed.connect(execute_fire_employee)
	
	# 当 PopupWindow 发出 canceled 信号时，执行取消逻辑（可选）
	popup_window.canceled.connect(cancel_fire_employee)
	
	set_process_input(true)

func _input(event: InputEvent) -> void:
	# 只处理鼠标左键按下
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not visible: 
			return
		
		# 1. 如果点在面板内部，绝对不能关
		if _is_pos_inside_panel(event.global_position):
			return
		
		# 2. 如果点在任何一个员工身上，也绝对不能关
		# 因为员工自己的 _gui_input 会去调用 open_panel()，如果这里关了就会冲突
		if _is_pos_on_any_employee(event.global_position):
			print("[Panel] 点击在员工身上，保持面板开启")
			return
		
		# 3. 只有点在既不是面板、也不是员工的“纯空白地带”，才执行关闭
		print("[Panel] 点击了空白处，关闭面板")
		close_panel()
			
func open_panel(employee: Employee) -> void:
	if employee == null:
		return
	
	# 🌟 第一重保护：如果点的是同一个人，且面板开着，直接无视，不重刷信号也不播动画
	if visible and current_employee == employee:
		return
	
	# 如果换了人，或者面板本来是关着的，才执行下面的刷新
	_disconnect_current_employee() # 换人前先把旧的断了
	current_employee = employee
	
	# ==========================================
	# 🚨 【这里是之前丢失的“三维”刷新代码】
	# ==========================================
	name_label.text = employee.employee_name
	
	# 刷新稀有度
	match employee.rarity:
		Employee.Rarity.R: rarity_label.text = "R"
		Employee.Rarity.SR: rarity_label.text = "SR"
		Employee.Rarity.SSR: rarity_label.text = "SSR"
	
	# 🌟 刷新属性条（确保你的节点引用名和这里一致）
	efficiency_bar.set_value(employee.efficiency)
	quality_bar.set_value(employee.quality)
	experience_bar.set_value(employee.experience)
	
	# 顺便设置颜色（如果你需要的话）
	efficiency_bar.set_bar_color(Color.SKY_BLUE)
	quality_bar.set_bar_color(Color.YELLOW)
	experience_bar.set_bar_color(Color.PALE_GREEN)
	# ==========================================
	
	if employee.portrait:
		# 🌟 改成这一句：直接把立绘节点(figure)交给 Helper 处理
		AvatarHelper.apply_portrait(figure, employee.portrait)
		
	# --- 刷新 UI (这部分保持原样) ---
	name_label.text = employee.employee_name
	# ... 你的 rarity_label, bars 等刷新代码 ...
	
	_refresh_progress_bar()
	_refresh_buffs()
	_update_dispatch_button()
	_connect_current_employee()
	
	# 🌟 第二重保护：只在面板还没出来时才播动画/show
	if not visible:
		show()
		# 如果你有入场动画，在这里播：$AnimationPlayer.play("fade_in")
	
	popup_window.hide() # 换人时把之前的弹窗藏了

func close_panel() -> void:
	_disconnect_current_employee()
	current_employee = null
	progress_bar.value = 0
	hide()

func _on_click_blocker_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_panel()

# ==========================================
# 4. 进度条联动
# ==========================================
func _connect_current_employee() -> void:
	if current_employee == null:
		return

	if not current_employee.work_progress_changed.is_connected(_on_work_progress_changed):
		current_employee.work_progress_changed.connect(_on_work_progress_changed)

	if not current_employee.work_started.is_connected(_on_work_started):
		current_employee.work_started.connect(_on_work_started)

	if not current_employee.work_stopped.is_connected(_on_work_stopped):
		current_employee.work_stopped.connect(_on_work_stopped)

	if not current_employee.tree_exiting.is_connected(_on_current_employee_tree_exiting):
		current_employee.tree_exiting.connect(_on_current_employee_tree_exiting)
	if not current_employee.buff_status_changed.is_connected(_refresh_buffs):
		current_employee.buff_status_changed.connect(_refresh_buffs)
	print("[EmployeePanel] 已连接进度信号 -> ", current_employee.employee_name)


func _disconnect_current_employee() -> void:
	if current_employee == null:
		return

	if current_employee.work_progress_changed.is_connected(_on_work_progress_changed):
		current_employee.work_progress_changed.disconnect(_on_work_progress_changed)

	if current_employee.work_started.is_connected(_on_work_started):
		current_employee.work_started.disconnect(_on_work_started)

	if current_employee.work_stopped.is_connected(_on_work_stopped):
		current_employee.work_stopped.disconnect(_on_work_stopped)

	if current_employee.tree_exiting.is_connected(_on_current_employee_tree_exiting):
		current_employee.tree_exiting.disconnect(_on_current_employee_tree_exiting)
	if current_employee.buff_status_changed.is_connected(_refresh_buffs):
		current_employee.buff_status_changed.disconnect(_refresh_buffs)

func _refresh_progress_bar() -> void:
	if current_employee == null:
		progress_bar.value = 0
		return

	progress_bar.value = current_employee.get_work_progress_percent()


func _on_work_progress_changed(progress_percent: float) -> void:
	progress_bar.value = progress_percent


func _on_work_started() -> void:
	progress_bar.value = 0


func _on_work_stopped() -> void:
	progress_bar.value = 0


func _on_work_cycle_completed(_reward_amount: int) -> void:
	progress_bar.value = 0


func _on_current_employee_tree_exiting() -> void:
	current_employee = null
	progress_bar.value = 0
	hide()
# ==========================================
# 5. 外派与调入逻辑
# ==========================================

func _is_employee_on_map() -> bool:
	if current_employee == null:
		return false
		
	# 1. 在工位上？算在地图上
	if current_employee.get("current_seat") != null:
		return true
		
	# 2. 没在工位，但在掉落组里，且确实在场景里？算在地图上
	if current_employee.is_in_group("dropped_employee") and current_employee.is_inside_tree():
		return true
			
	return false

func _update_dispatch_button() -> void:
	if current_employee == null: return
	
	if _is_employee_on_map():
		dispatch_btn_label.text = "Recall"
	else:
		dispatch_btn_label.text = "Dispatch"

func _on_dispatch_pressed() -> void:
	if current_employee == null: return
	
	if _is_employee_on_map():
		# ======= 【调回 (Recall) 逻辑】 =======
		print("把员工从地图收回仓库：", current_employee.employee_name)
		
		# 1. 如果在工位上，让他从工位上下来
		if current_employee.get("current_seat") != null:
			current_employee.current_seat.clear_occupant()
			current_employee.current_seat = null
			
		# 2. 直接对他施加封印（不需要去地图上找了！）
		if current_employee.has_method("set_inactive"):
			current_employee.set_inactive()
		else:
			# 保底逻辑
			current_employee.visible = false
			current_employee.mouse_filter = Control.MOUSE_FILTER_IGNORE
			current_employee.process_mode = Node.PROCESS_MODE_DISABLED
			if current_employee.is_in_group("dropped_employee"):
				current_employee.remove_from_group("dropped_employee")
			if current_employee.get_parent():
				current_employee.get_parent().remove_child(current_employee)
				
		progress_bar.value = 0
		
	else:
		# ======= 【派遣 (Dispatch) 逻辑】 =======
		print("把员工扔进地图：", current_employee.employee_name)
		# 🚨 【核心修复点】：如果他还在内存的某个角落挂着父节点
		# 必须先解绑，DropArea 那边的 add_child 才能成功
		if current_employee.get_parent():
			current_employee.get_parent().remove_child(current_employee)
		
		Gamemanager.request_employee_drop.emit(current_employee)
	
	# 刷新按钮文字
	_update_dispatch_button()
# ==========================================
# 6. 优化(开除)弹窗逻辑
# ==========================================
func _on_fire_pressed() -> void:
# 在显示弹窗前，动态设置一下文本（利用你写的 set 属性）
	popup_window.title_text = "Are you sure to fire " + current_employee.employee_name + " ？"
	popup_window.confirm_label = "Sure"
	popup_window.cancel_label = "Wait"
	popup_window.show()

func execute_fire_employee() -> void:
	if current_employee != null:
		# 1. 腾出工位
		if current_employee.get("current_seat") != null:
			current_employee.current_seat.clear_occupant()
		
		# （这里原本有去地图找名字并 queue_free 的逻辑，直接删掉！
		# 因为最后一步的 current_employee.queue_free() 会自动把地图上的他一起带走）
		
		# 2. 返还资源的逻辑
		if current_employee.rarity == Employee.Rarity.SR or current_employee.rarity == Employee.Rarity.SSR:
			print("退还了少量美金！")
		
		# 3. 通知其他系统员工已离职
		EmployeeManager.employee_removed.emit(current_employee)
		
		# 4. 从 Manager 的主列表中移除
		EmployeeManager.my_employees.erase(current_employee)
		
		# 5. 【最后一步】：彻底销毁员工数据和地图实体
		current_employee.queue_free()
		current_employee = null
		
	popup_window.hide()
	close_panel()

# ⚠️ 注意：你需要将你的 PopupWindow 里的“取消”按钮信号连接到这个函数！
func cancel_fire_employee() -> void:
	popup_window.hide()

# ==========================================
# 7. Buff 显示逻辑
# ==========================================
func _refresh_buffs() -> void:
	# 1. 每次打开面板前，先把旧的 Buff 标签清空，防止无限叠加
	for child in buffs_container.get_children():
		child.queue_free()
		
	if current_employee == null:
		return
		
	var has_any_buff = false
	
	# ==========================================
	# 🌟 重点：在这里增加会议 Buff 的动态展示
	# ==========================================
	if current_employee.is_in_meeting:
		# 我们把那一串跳动的随机数直接打在标签上
		var q_val = current_employee.meet_buff_qual
		var e_val = current_employee.meet_buff_exp
		var eff_val = current_employee.meet_buff_eff
		
		# 构造一个看起来就很专业的 Buff 描述
		var meeting_text = "会议头脑风暴中"
		var details = "本轮加成：\n"
		details += "✨ 质量 + " + str(q_val) + "\n"
		details += "📈 经验 + " + str(e_val) + "\n"
		details += "⏳ 效率 " + str(eff_val) + " (会议开销)"
		
		_add_buff_label(meeting_text, details)
		has_any_buff = true
		
	# 2. 检查是否有【工位 Buff】
	if current_employee.get("current_seat") != null:
		var seat = current_employee.current_seat
		var eff_buff = 0
		var qual_buff = 0
		
		# 读取工位的增益（使用你之前写好的接口）
		if seat.has_method("get_efficiency_buff"):
			eff_buff = seat.get_efficiency_buff()
		if seat.has_method("get_quality_buff"):
			qual_buff = seat.get_quality_buff()
			
		# 如果工位确实提供了 Buff，就生成一条标签
		if eff_buff > 0 or qual_buff > 0:
			var desc = "当前工位提供:\n"
			if eff_buff > 0: desc += "效率 +" + str(eff_buff) + " "
			if qual_buff > 0: desc += "质量 +" + str(qual_buff)
			
			# 调用添加标签的函数 (显示的名字, 悬停的解释)
			_add_buff_label("办公桌增益", desc)
			has_any_buff = true
			
	# 3. 检查是否有【文化 Buff】		
	if OfficeManager.culture_efficiency > 0:
		_add_buff_label("企业文化", "全公司效率 +" + str(OfficeManager.culture_efficiency))
	if OfficeManager.culture_experience > 0:
		_add_buff_label("企业文化", "全公司效率 +" + str(OfficeManager.culture_experience))
	if OfficeManager.culture_quality > 0:
		_add_buff_label("企业文化", "全公司效率 +" + str(OfficeManager.culture_quality))
	# 4. 检查是否有【零食 Buff】	
	if current_employee.get("current_snack_buff") != null:
		var snack = current_employee.current_snack_buff
		
		# 利用你在 Employee.gd 里定义的枚举
		# 这里注意：如果 Employee.gd 里枚举没加 class_name，可能需要用 employee.SnackBuff
		match snack:
			1: # MILK_TEA (对应你定义的 1: 奶茶)
				_add_buff_label("奶茶增益", "茶水间供应：本次产出效率 +3")
			2: # CAKE (对应你定义的 2: 蛋糕)
				_add_buff_label("蛋糕增益", "茶水间供应：本次产出质量 +3")
			3: # SAUSAGE (对应你定义的 3: 烤肠)
				_add_buff_label("烤肠增益", "茶水间供应：本次产出经验 +3")
		# 4. 如果什么 Buff 都没有，显示一句提示（可选）
	#if not has_any_buff:
		#_add_buff_label("无增益", "该员工当前没有任何状态加成")
# 动态生成一条 Buff 标签的辅助函数
func _add_buff_label(buff_name: String, hover_description: String) -> void:
	var label = Label.new()
	label.text = "✦ " + buff_name
	
	# 🚨 【核心魔法】：Godot 原生悬停提示！
	label.tooltip_text = hover_description
	
	# 必须开启鼠标阻挡，否则悬停提示弹不出来
	label.mouse_filter = Control.MOUSE_FILTER_STOP 
	
	# （可选）给 Buff 换个显眼的颜色
	if buff_name != "无增益":
		label.add_theme_color_override("font_color", Color.GREEN_YELLOW)
	else:
		label.add_theme_color_override("font_color", Color.GRAY)
		
	# 把生成好的标签塞进容器里
	buffs_container.add_child(label)

func _is_pos_inside_panel(global_pos: Vector2) -> bool:
	# 这里的 $PanelBg 是你面板的实际可见区域
	return $PanelBg.get_global_rect().has_point(global_pos)

func _is_pos_on_any_employee(global_pos: Vector2) -> bool:
	# 遍历所有在 "employees" 组里的节点
	var all_employees = get_tree().get_nodes_in_group("employees")
	for emp in all_employees:
		if emp is Control:
			# 检查鼠标位置是否在员工的矩形范围内
			if emp.get_global_rect().has_point(global_pos):
				return true
	return false
