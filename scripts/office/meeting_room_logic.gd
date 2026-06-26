# meeting_room_logic.gd
extends OfficeLogic
class_name MeetingRoomLogic

const MAX_CAPACITY = 6

# ==========================================
# 🌟 头像裁剪参数（露出完整头部 + 面部，填满方框）—— 想微调改这三个：
#   AVATAR_FRAME_SIZE : 头像框大小（正方形）
#   HEAD_ZOOM         : 放大倍数，越大头/脸越大
#   HEAD_FOCUS_*      : 把立绘上的这一行像素对准框中心；越小越往头顶
# R 卡角色图小、SR/SSR 填满格子，头在框里高度不同，所以两套 focus。
# ==========================================
const AVATAR_FRAME_SIZE := Vector2(56, 56)
const HEAD_ZOOM := 2.0
const HEAD_FOCUS_R := 16.0    # R 卡（脸在立绘偏下，focus 要大才能把脸框到中心）
const HEAD_FOCUS_HIGH := 18.0 # SR / SSR

var attendees: Array = [] # 正在开会的 Employee 节点引用

# Office.tscn 里手动摆放的节点
var parent_office: Control
var slots_container: GridContainer # 房间下方的 AvatarSlots（6 个 Slot）
var dismiss_btn: TextureButton     # 房间中心、悬停出现的"解散会议"按钮

func setup(office: Control) -> void:
	super.setup(office)
	parent_office = office

	slots_container = parent_office.get_node("AvatarSlots")
	dismiss_btn = parent_office.get_node("DismissButton")

	slots_container.show()
	_update_avatars()

	# 解散按钮：初始隐藏，连接信号（鼠标悬停会议室时才显示）
	dismiss_btn.hide()
	if not dismiss_btn.pressed.is_connected(dismiss_meeting):
		dismiss_btn.pressed.connect(dismiss_meeting)

func cleanup() -> void:
	# 离开会议室（如切换成茶水间）时，先把所有人遣散回工位
	dismiss_meeting()

	# 千万别销毁，只是藏起来，否则下次切回来节点就没了
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
		# 必须有工位才能进会议室，DropArea 里的新人进不来
		var has_seat = data.get("current_seat") != null or data.get("drag_start_seat") != null
		if has_seat and attendees.size() < MAX_CAPACITY and not attendees.has(data):
			return true
	return false

func drop_employee(data: Variant) -> void:
	var emp = data
	attendees.append(emp)
	emp.enter_meeting() # 隐身、霸占工位、加Buff、进度归零
	_update_avatars()
	#[员工吐槽中心]：会议开始
	BanterManager.trigger_banter("meeting_start", randi_range(1, 2), attendees)

# ==========================================
# 悬停：会议室图像中心出现"解散会议"按钮
# ==========================================
func on_mouse_entered():
	if attendees.size() > 0 and is_instance_valid(dismiss_btn):
		dismiss_btn.show()

func on_mouse_exited(mouse_pos: Vector2):
	if not is_instance_valid(dismiss_btn): return
	# 鼠标真的离开了房间区域（且没停在按钮上）才隐藏
	var room_rect = parent_office.get_global_rect()
	var btn_rect = dismiss_btn.get_global_rect()
	if not room_rect.has_point(mouse_pos) and not btn_rect.has_point(mouse_pos):
		dismiss_btn.hide()

# ==========================================
# 🌟 把参会员工对号入座到下方头像槽：头部头像（双击退出）+ 名字
# ==========================================
func _update_avatars():
	if not is_instance_valid(slots_container): return

	var slots = slots_container.get_children()
	for i in range(slots.size()):
		var slot = slots[i]
		for child in slot.get_children():
			child.queue_free()
		if i < attendees.size():
			_build_avatar_slot(slot, attendees[i])

func _build_avatar_slot(slot: Control, emp) -> void:
	# ---------- 头像框（裁剪到头部+面部）----------
	# 用 Control（而非 Button）以便检测双击；clip 把超出框的身体裁掉
	var frame := Control.new()
	frame.clip_contents = true
	frame.custom_minimum_size = AVATAR_FRAME_SIZE
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_STOP

	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE # 点击穿透给 frame
	holder.size = AVATAR_FRAME_SIZE
	# 让立绘上的 (中心X, focus_y) 固定落在框正中心，再放大裁出头部+面部
	var focus_y: float = HEAD_FOCUS_R if int(emp.rarity) == int(Employee.Rarity.R) else HEAD_FOCUS_HIGH
	holder.pivot_offset = Vector2(AVATAR_FRAME_SIZE.x * 0.5, focus_y)
	holder.position = Vector2(0.0, AVATAR_FRAME_SIZE.y * 0.5 - focus_y)
	holder.scale = Vector2(HEAD_ZOOM, HEAD_ZOOM)
	frame.add_child(holder)
	AvatarHelper.apply_portrait(holder, emp.portrait, emp.rarity)

	# 🌟 双击头像 → 该员工退出会议
	frame.gui_input.connect(func(ev): _on_avatar_gui_input(ev, emp))
	frame.mouse_entered.connect(func(): frame.modulate = Color(1.2, 1.2, 1.2))
	frame.mouse_exited.connect(func(): frame.modulate = Color(1, 1, 1))
	slot.add_child(frame)

	# ---------- 名字标签 ----------
	var name_label := Label.new()
	name_label.text = emp.get_display_name() if emp.has_method("get_display_name") else str(emp.employee_name)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	name_label.custom_minimum_size = Vector2(AVATAR_FRAME_SIZE.x, 0)
	name_label.add_theme_font_size_override("font_size", 12)
	slot.add_child(name_label)

	# 玩家在仓库改名时，同步刷新这个会议头像下的名字标签
	if emp.has_signal("display_name_changed"):
		var updater := func():
			if is_instance_valid(name_label):
				name_label.text = emp.get_display_name() if emp.has_method("get_display_name") else str(emp.employee_name)
		emp.display_name_changed.connect(updater)
		# 标签被重建/销毁时断开连接，避免连接在 emp 上越积越多
		name_label.tree_exited.connect(func():
			if is_instance_valid(emp) and emp.display_name_changed.is_connected(updater):
				emp.display_name_changed.disconnect(updater)
		)

func _on_avatar_gui_input(event: InputEvent, emp) -> void:
	# 只认左键双击
	if event is InputEventMouseButton and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
		_remove_attendee(emp)

# ==========================================
# 单人退出：双击哪个头像，哪个员工回工位
# ==========================================
func _remove_attendee(emp) -> void:
	if not attendees.has(emp): return

	attendees.erase(emp)
	if is_instance_valid(emp):
		emp.exit_meeting(_get_meeting_exit_source_pos())
		#[员工吐槽中心]：散会
		BanterManager.trigger_banter("meeting_end", 1, [emp])

	_update_avatars()
	# 没人了就把解散按钮收起来
	if attendees.is_empty() and is_instance_valid(dismiss_btn):
		dismiss_btn.hide()

# ==========================================
# 整体遣散：点会议室中心的解散按钮，全体回工位
# ==========================================
func dismiss_meeting():
	if attendees.is_empty():
		if is_instance_valid(dismiss_btn): dismiss_btn.hide()
		return
	#[员工吐槽中心]：会议结束
	BanterManager.trigger_banter("meeting_end", 3, attendees.duplicate())
	var exit_source_pos := _get_meeting_exit_source_pos()
	for emp in attendees:
		if is_instance_valid(emp):
			emp.exit_meeting(exit_source_pos)

	attendees.clear()
	_update_avatars()
	if is_instance_valid(dismiss_btn):
		dismiss_btn.hide()

func _get_meeting_exit_source_pos() -> Vector2:
	if is_instance_valid(parent_office):
		return parent_office.get_global_rect().get_center()
	return Vector2.ZERO
