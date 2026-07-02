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

const AUTO_DISMISS_SECONDS := 3600.0   # 会议自动散会时间(1 小时 = 3600 秒;随游戏倍速变快)
var _auto_dismiss_timer: Timer = null

# 解散按钮在会议室贴图外，鼠标从贴图挪向按钮的途中会先"离开"会议室。
# 所以离开后不立刻收，而是给一段宽限时间(够把鼠标移到按钮上)，期间碰到按钮就取消收起。
const DISMISS_BTN_HIDE_GRACE := 0.6
var _dismiss_hide_timer: Timer = null

# 错开散会：点解散/超时后，每个人随机延迟这个区间(秒)再离开，不要全体同时起身
const DISMISS_STAGGER_MIN := 0.2
const DISMISS_STAGGER_MAX := 1.0
var _dismissing: bool = false   # 正在错开遣散中，期间不许再拖人进来/重复触发

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
	# 悬停按钮本身时取消收起、移开按钮时启动宽限收起——配合会议室的悬停，解决"够不到"
	if not dismiss_btn.mouse_entered.is_connected(_on_dismiss_btn_mouse_entered):
		dismiss_btn.mouse_entered.connect(_on_dismiss_btn_mouse_entered)
	if not dismiss_btn.mouse_exited.is_connected(_on_dismiss_btn_mouse_exited):
		dismiss_btn.mouse_exited.connect(_on_dismiss_btn_mouse_exited)

	# 收起解散按钮的宽限计时器（离开会议室/按钮后延迟收起，期间可被取消）
	_dismiss_hide_timer = Timer.new()
	_dismiss_hide_timer.one_shot = true
	_dismiss_hide_timer.wait_time = DISMISS_BTN_HIDE_GRACE
	_dismiss_hide_timer.timeout.connect(_hide_dismiss_btn_now)
	add_child(_dismiss_hide_timer)

	# 自动散会:开会满 1 小时,即使玩家不点也自动散会
	_auto_dismiss_timer = Timer.new()
	_auto_dismiss_timer.one_shot = true
	_auto_dismiss_timer.wait_time = AUTO_DISMISS_SECONDS
	_auto_dismiss_timer.timeout.connect(dismiss_meeting)
	add_child(_auto_dismiss_timer)

	# 监听开除:开会中的员工被开掉时,立刻清掉它的会议头像 + 办公桌开会标志
	if not EmployeeManager.employee_removed.is_connected(_on_employee_removed):
		EmployeeManager.employee_removed.connect(_on_employee_removed)

func cleanup() -> void:
	# 离开会议室（如切换成茶水间）时，先把所有人遣散回工位。
	# 这里必须"立刻全体遣散"：cleanup 结尾会 queue_free 本逻辑节点，
	# 用错开延迟版会因节点被销毁而中断，员工卡在开会态。
	_dismiss_all_immediately()

	# 撤掉开除监听(本逻辑节点即将销毁)
	if EmployeeManager.employee_removed.is_connected(_on_employee_removed):
		EmployeeManager.employee_removed.disconnect(_on_employee_removed)

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
		if has_seat and not _dismissing and attendees.size() < MAX_CAPACITY and not attendees.has(data):
			return true
	return false

func drop_employee(data: Variant) -> void:
	var emp = data
	attendees.append(emp)
	emp.enter_meeting() # 隐身、霸占工位、加Buff、进度归零
	# 第一个人进来 = 会议开始,启动 1 小时自动散会倒计时
	if attendees.size() == 1 and is_instance_valid(_auto_dismiss_timer):
		_auto_dismiss_timer.start()
	_update_avatars()
	#[员工吐槽中心]：会议开始
	BanterManager.trigger_banter("meeting_start", randi_range(1, 2), attendees)

# ==========================================
# 🌟 读档专用：把一个原本在开会的员工重新登记回会议室
# 参会名单(attendees)是运行时数据、存档没存；读档时若只对员工 enter_meeting，
# 它会隐身却不在 attendees 里 → 没头像、无法散会 → 永久"消失"。故此方法补上登记。
# 与 drop_employee 的区别：不触发"会议开始"吐槽、并容忍员工已处于开会态。
# ==========================================
func restore_attendee(emp) -> void:
	if emp == null or attendees.has(emp):
		return
	if attendees.size() >= MAX_CAPACITY:
		return
	# 让员工进入开会态（隐身、会议 Buff、进度归零）。读档时 drag_start_seat 为空，
	# enter_meeting 内的"占座 + 开会标志"分支会被跳过，所以下面手动补开会标志。
	if not emp.is_in_meeting:
		emp.enter_meeting()
	attendees.append(emp)
	if emp.get("current_seat") != null and emp.current_seat.has_method("set_meeting_state"):
		emp.current_seat.set_meeting_state(true)
	_update_avatars()
	# 会议仍在进行：确保自动散会计时在跑（多人恢复时只第一个真正启动）
	if is_instance_valid(_auto_dismiss_timer) and _auto_dismiss_timer.is_stopped():
		_auto_dismiss_timer.start()

# ==========================================
# 悬停：会议室图像中心出现"解散会议"按钮
# ==========================================
func on_mouse_entered():
	if attendees.size() > 0 and is_instance_valid(dismiss_btn):
		_cancel_dismiss_hide()   # 回到会议室，取消正在倒计时的收起
		dismiss_btn.show()

func on_mouse_exited(_mouse_pos: Vector2):
	# 不再瞬间收起：启动宽限倒计时，给玩家时间把鼠标移到（贴图外的）解散按钮上。
	# 若途中碰到按钮，其 mouse_entered 会取消这次收起。
	_start_dismiss_hide()

# —— 解散按钮自身的悬停：悬上就别收，移开就开始倒计时收起 ——
func _on_dismiss_btn_mouse_entered() -> void:
	_cancel_dismiss_hide()

func _on_dismiss_btn_mouse_exited() -> void:
	_start_dismiss_hide()

func _start_dismiss_hide() -> void:
	if is_instance_valid(_dismiss_hide_timer):
		_dismiss_hide_timer.start()   # one_shot，重复 start 会重置倒计时

func _cancel_dismiss_hide() -> void:
	if is_instance_valid(_dismiss_hide_timer):
		_dismiss_hide_timer.stop()

func _hide_dismiss_btn_now() -> void:
	if is_instance_valid(dismiss_btn):
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
	# 🌟 悬停头像 → 弹出该员工的信息面板；移开 → 关闭
	frame.mouse_entered.connect(func():
		frame.modulate = Color(1.2, 1.2, 1.2)
		_show_employee_panel(emp)
	)
	frame.mouse_exited.connect(func():
		frame.modulate = Color(1, 1, 1)
		_hide_employee_panel()
	)
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

# ==========================================
# 🌟 悬停会议头像时，弹出/收起对应员工的信息面板
# 面板是全局单例（employee_panel 组），点击工位上的员工也是用它。
# ==========================================
func _show_employee_panel(emp) -> void:
	if not is_instance_valid(emp):
		return
	var panel = get_tree().get_first_node_in_group("employee_panel")
	if panel and panel.has_method("open_panel"):
		panel.open_panel(emp)

func _hide_employee_panel() -> void:
	var panel = get_tree().get_first_node_in_group("employee_panel")
	if panel and panel.has_method("close_panel"):
		panel.close_panel()

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
	# 没人了就把解散按钮收起来,并停掉自动散会计时
	if attendees.is_empty():
		if is_instance_valid(_auto_dismiss_timer):
			_auto_dismiss_timer.stop()
		if is_instance_valid(dismiss_btn):
			dismiss_btn.hide()

# ==========================================
# 🌟 开会中的员工被开除:立刻撤掉它的会议头像 + 办公桌开会标志
# (employee_removed 在 EmployeeManager 里于 queue_free 之前发出,
#  所以此刻 emp 与它的 current_seat 仍有效,可安全清理)
# ==========================================
func _on_employee_removed(emp) -> void:
	if not attendees.has(emp):
		return
	if is_instance_valid(emp) and emp.get("current_seat") != null \
	and emp.current_seat.has_method("set_meeting_state"):
		emp.current_seat.set_meeting_state(false)   # 去掉办公桌上的开会标志
	attendees.erase(emp)
	_update_avatars()                                # 把它的头像从会议室移除
	if attendees.is_empty():
		_dismissing = false                          # 散会进行中把最后一人开除了，复位状态
		if is_instance_valid(_auto_dismiss_timer):
			_auto_dismiss_timer.stop()
		if is_instance_valid(dismiss_btn):
			dismiss_btn.hide()

# ==========================================
# 整体遣散：点会议室中心的解散按钮 / 自动超时。
# 不让全体同时起身——每人随机延迟 0.2~1s 各自离开，头像也随之一个个消失。
# ==========================================
func dismiss_meeting():
	# 不论怎么散会(玩家点 / 超时 / 清空),都先停掉自动散会计时
	if is_instance_valid(_auto_dismiss_timer):
		_auto_dismiss_timer.stop()
	if attendees.is_empty():
		if is_instance_valid(dismiss_btn): dismiss_btn.hide()
		return
	if _dismissing:
		return   # 已在错开遣散中，别重复排队
	_dismissing = true
	#[员工吐槽中心]：会议结束
	BanterManager.trigger_banter("meeting_end", 3, attendees.duplicate())
	var exit_source_pos := _get_meeting_exit_source_pos()
	# 会议已结束：解散按钮立刻收起，防止散会过程中再点
	if is_instance_valid(dismiss_btn):
		dismiss_btn.hide()
	# 给每个人各排一个随机延迟的离开计时，错开起身
	for emp in attendees.duplicate():
		var delay := randf_range(DISMISS_STAGGER_MIN, DISMISS_STAGGER_MAX)
		get_tree().create_timer(delay).timeout.connect(
			_release_attendee_on_dismiss.bind(emp, exit_source_pos)
		)

# 错开遣散：单个员工延迟到点后离开，并移除他的头像
func _release_attendee_on_dismiss(emp, exit_source_pos: Vector2) -> void:
	if attendees.has(emp):
		attendees.erase(emp)
		if is_instance_valid(emp):
			emp.exit_meeting(exit_source_pos)
		_update_avatars()   # 重建头像 → 该员工的头像随之消失
	# 全部走光后复位状态
	if attendees.is_empty():
		_dismissing = false
		if is_instance_valid(dismiss_btn):
			dismiss_btn.hide()

# 立刻全体遣散（切换房间/清理时用，不能异步延迟）
func _dismiss_all_immediately() -> void:
	if is_instance_valid(_auto_dismiss_timer):
		_auto_dismiss_timer.stop()
	if attendees.is_empty():
		_dismissing = false
		if is_instance_valid(dismiss_btn): dismiss_btn.hide()
		return
	#[员工吐槽中心]：会议结束
	BanterManager.trigger_banter("meeting_end", 3, attendees.duplicate())
	var exit_source_pos := _get_meeting_exit_source_pos()
	for emp in attendees:
		if is_instance_valid(emp):
			emp.exit_meeting(exit_source_pos)
	attendees.clear()
	_dismissing = false
	_update_avatars()
	if is_instance_valid(dismiss_btn):
		dismiss_btn.hide()

func _get_meeting_exit_source_pos() -> Vector2:
	if is_instance_valid(parent_office):
		return parent_office.get_global_rect().get_center()
	return Vector2.ZERO
