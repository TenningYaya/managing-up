# meeting_room_logic.gd
extends OfficeLogic
class_name MeetingRoomLogic

const MAX_CAPACITY = 6
var attendees: Array = [] # 存放正在开会的 Employee 节点引用

# 引用 Office.tscn 里的手动摆放节点
var parent_office: Control
var slots_container: GridContainer # 你改名后的 AvatarSlots (GridContainer)
var dismiss_btn: TextureButton

func setup(office: Control) -> void:
	super.setup(office)
	parent_office = office

	# 🌟 1. 获取场景中手动摆好的“插槽容器”
	# 确保你在场景里的节点名字叫 AvatarSlots
	slots_container = parent_office.get_node("AvatarSlots")
	dismiss_btn = parent_office.get_node("DismissButton")

	# 🌟 2. 激活显示
	slots_container.show()
	
	# 初始化：清空所有 Slot 里的残留内容并重绘
	_update_avatars()

	# 初始状态隐藏按钮，连接信号
	dismiss_btn.hide()
	if not dismiss_btn.pressed.is_connected(dismiss_meeting):
		dismiss_btn.pressed.connect(dismiss_meeting)

func cleanup() -> void:
	# 离开会议室逻辑（如切换到茶水间）时，先遣散员工
	dismiss_meeting()
	
	# 🌟 3. 核心修复：千万别销毁，只是藏起来，否则下次切换回来节点就没了
	if is_instance_valid(slots_container): 
		slots_container.hide()
	if is_instance_valid(dismiss_btn): 
		dismiss_btn.hide()
		
	queue_free() # 销毁逻辑脚本实例

# ==========================================
# 拖拽检测逻辑
# ==========================================
func can_drop_employee(data: Variant) -> bool:
	if data is Node and data.has_method("enter_meeting"):
		# 🌟 核心修改：必须有工位 (current_seat) 才能进会议室
		# 这样 DropArea 里的新人或正在被拖拽的人就进不来了
		var has_seat = data.get("current_seat") != null or data.get("drag_start_seat") != null
		
		if has_seat and attendees.size() < MAX_CAPACITY and not attendees.has(data):
			return true
	return false
	
func drop_employee(data: Variant) -> void:
	var emp = data
	attendees.append(emp)
	
	# 执行员工入会逻辑（隐身、霸占工位、加Buff、进度归零）
	emp.enter_meeting() 
	
	# 刷新 UI 显示
	_update_avatars()

# ==========================================
# 悬停显示逻辑 (Dismiss 按钮)
# ==========================================
func on_mouse_entered():
	# 只要屋子里有人开会，鼠标滑过就显示解散按钮
	if attendees.size() > 0:
		dismiss_btn.show()

func on_mouse_exited(mouse_pos: Vector2):
	# 判定鼠标是否真的离开了办公室区域（且没在按钮上）
	var room_rect = parent_office.get_global_rect()
	var btn_rect = dismiss_btn.get_global_rect()
	
	if not room_rect.has_point(mouse_pos) and not btn_rect.has_point(mouse_pos):
		dismiss_btn.hide()

# ==========================================
# 🌟 核心：对号入座显示逻辑
# ==========================================
func _update_avatars():
	if not is_instance_valid(slots_container): return
	
	# 获取你手动摆好的 6 个 CenterContainer 插槽
	var slots = slots_container.get_children()
	
	for i in range(slots.size()):
		var slot = slots[i] # 这是一个 CenterContainer
		
		# 1. 清空当前插槽
		for child in slot.get_children():
			child.queue_free()
		
		# 2. 如果当前索引有对应的开会员工，生成头像
		if i < attendees.size():
			var emp = attendees[i]
			var btn = TextureButton.new()
			
			# --- 核心 UI 配置 ---
			# 因为外层是 CenterContainer，它会把这个 btn 自动锁在格子正中心
			btn.custom_minimum_size = Vector2(80, 80) # 建议设为和你 Slot 一样大
			btn.ignore_texture_size = true
			btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
			
			# 🌟 调用你封装好的 AvatarHelper 
			# 这句会全自动处理：底图 + 衣服 + 头发 + 像素对齐
			AvatarHelper.apply_portrait(btn, emp.portrait)
			
			# 绑定点击查看面板
			btn.pressed.connect(func(): _open_employee_panel(emp))
			
			# 增加一点悬停反馈
			btn.mouse_entered.connect(func(): btn.modulate = Color(1.2, 1.2, 1.2))
			btn.mouse_exited.connect(func(): btn.modulate = Color(1, 1, 1))
			
			# 塞进插槽
			slot.add_child(btn)

func _open_employee_panel(emp):
	var panel = parent_office.get_tree().get_first_node_in_group("employee_panel")
	if panel and panel.has_method("open_panel"):
		panel.open_panel(emp)

# ==========================================
# 核心结算：解散会议
# ==========================================
func dismiss_meeting():
	if attendees.is_empty(): return
	
	# 让所有参会人员滚回工位，清除会议 Buff
	for emp in attendees:
		if is_instance_valid(emp):
			emp.exit_meeting()
			
	attendees.clear()
	_update_avatars()
	dismiss_btn.hide()
