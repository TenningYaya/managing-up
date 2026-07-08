#employee_panel.gd
extends Control
class_name EmployeePanel

# ==========================================
# 1. 节点引用 (严格对应截图层级)
# ==========================================
# --- 员工信息部分 ---
@onready var figure: TextureRect = $PanelBg/EmployeePage/NameCard/Figure
@onready var name_label: HBoxContainer = $PanelBg/EmployeePage/NameCard/MarginContainer/InfoContainer/NameLabel
@onready var rarity_label: HBoxContainer = $PanelBg/EmployeePage/NameCard/MarginContainer/InfoContainer/RarityLabel
@onready var attribute_label: HBoxContainer = $PanelBg/EmployeePage/NameCard/MarginContainer/InfoContainer/AttributeLabel

# --- 属性条组件部分 ---
@onready var efficiency_bar: EmployeeAbility = $PanelBg/EmployeePage/Information/Abilities/EfficiencyBar
@onready var quality_bar: EmployeeAbility = $PanelBg/EmployeePage/Information/Abilities/QualityBar
@onready var experience_bar: EmployeeAbility = $PanelBg/EmployeePage/Information/Abilities/ExperienceBar

@onready var progress_bar: TextureProgressBar = $PanelBg/EmployeePage/Information/ProgressBar/ProgressBar
@onready var working_status: Label = $PanelBg/EmployeePage/Information/ProgressBar/ProgressBar/WorkingStatus
@onready var fire_vfx: CanvasItem = $PanelBg/EmployeePage/Information/ProgressBar/ProgressBar/FireVfx

@onready var buffs_container: HFlowContainer = $PanelBg/EmployeePage/PanelContainer/MarginContainer/VBoxContainer/Buffs
const BUFF_TAG_SCENE = preload("res://scenes/sidebar/employee_panel/buff_tag.tscn")

# --- 底部按钮部分 ---
@onready var dispatch_btn: TextureButton = $PanelBg/EmployeePage/Manage/DispatchButton
@onready var fire_btn: TextureButton = $PanelBg/EmployeePage/Manage/NormalButton2 # 建议之后重命名为 FireButton
@onready var dispatch_btn_label: Label = $PanelBg/EmployeePage/Manage/DispatchButton/Label
@onready var go_meeting_btn: TextureButton = $PanelBg/EmployeePage/Manage/GoMeeting

# --- 弹窗部分 ---
@onready var popup_window = $PanelBg/PopupWindow
@onready var title_bar = $TitleBar

# 当前正在查看的员工数据引用
var current_employee: Employee = null
var is_locked_by_tutorial: bool = false
var _shake_tween: Tween = null

var dragging := false
var drag_offset := Vector2()

# 重命名相关（铅笔图标 + 名字字体，与名字标签一致）
const RENAME_ICON := preload("res://assets/sidebar/other/edit (1).png")
const NAME_FONT := preload("res://assets/fonts/standard.tres")
var _name_info_label: Label              # name_label(信息条) 内部那个显示文字的 Label
var _edit_name_button: TextureButton
var _name_edit: LineEdit
var _is_editing_name: bool = false
var _name_before_edit: String = ""

func lock_for_tutorial():
	is_locked_by_tutorial = true
	show() # 确保它显示出来

func unlock_from_tutorial():
	is_locked_by_tutorial = false

func setup(employee_node: Node) -> void:
	current_employee = employee_node
	# 强制全量刷新 UI
	_refresh_all_ui() 
	show()

func _refresh_all_ui() -> void:
	if not current_employee: return
	_refresh_progress_bar()
	_refresh_buffs()
	
func _ready() -> void:
	hide() 
	popup_window.hide()
	
	progress_bar.min_value = 0
	progress_bar.max_value = 100
	progress_bar.value = 0
	
	efficiency_bar.tooltip_text = tr("TOOLTIP_EMP_EFFICIENCY")
	quality_bar.tooltip_text = tr("TOOLTIP_EMP_QUALITY")
	experience_bar.tooltip_text = tr("TOOLTIP_EMP_EXPERIENCE")
	go_meeting_btn.tooltip_text = tr("TOOLTIP_GO_MEETING")

	# 绑定底部按钮事件
	dispatch_btn.pressed.connect(_on_dispatch_pressed)
	# 单个开除：按你的设计不走确认弹窗，直接开除（会顺带播螺旋升天特效）
	fire_btn.pressed.connect(execute_fire_employee)
	go_meeting_btn.pressed.connect(_on_go_meeting_pressed)
	# ------------------------------------------
	# 3. 这里是连接 PopupWindow 的地方！
	# ------------------------------------------
	# 当 PopupWindow 发出 confirmed 信号时，执行开除逻辑
	popup_window.confirmed.connect(execute_fire_employee)
	
	# 当 PopupWindow 发出 canceled 信号时，执行取消逻辑（可选）
	popup_window.canceled.connect(cancel_fire_employee)

	set_process_input(true)
	_build_panel_rename_ui()

# ==================== 名字行内重命名 ====================
# 只给 name_label 这一个信息条加铅笔按钮和编辑框（RarityLabel/AttributeLabel 共用同一组件，不能动）
func _build_panel_rename_ui() -> void:
	_name_info_label = name_label.get_node("InfoLabel")

	# name_label 是 HBoxContainer：默认把同排子项拉到与最高子项等高。编辑框（像素字体在 20 号下
	# 整行高约 29）比名字文字高，会撑高整行，而 InfoIcon 是 expand_mode=IGNORE_SIZE + 纵向填充，
	# 就被纵向拉长。把图标钉成不随行高拉伸（固定 20，居中），编辑时就不会再变形。
	var info_icon := name_label.get_node("InfoIcon") as Control
	if info_icon:
		info_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# 铅笔按钮：放在名字标签右侧
	_edit_name_button = TextureButton.new()
	_edit_name_button.name = "EditNameButton"
	_edit_name_button.texture_normal = RENAME_ICON
	_edit_name_button.ignore_texture_size = true
	_edit_name_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_edit_name_button.custom_minimum_size = Vector2(18, 18)
	_edit_name_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.add_child(_edit_name_button)
	_edit_name_button.pressed.connect(_start_panel_rename)

	# 行内编辑框：默认隐藏，编辑时顶替名字文字
	_name_edit = LineEdit.new()
	_name_edit.name = "NameEdit"
	_name_edit.max_length = 12
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.add_theme_font_override("font", NAME_FONT)
	_name_edit.add_theme_font_size_override("font_size", 20)
	_apply_compact_lineedit_style(_name_edit)   # 收窄上下边距，使其高度≈名字文字，避免撑高整行
	_name_edit.hide()
	name_label.add_child(_name_edit)
	_name_edit.text_submitted.connect(_on_panel_name_submitted)
	_name_edit.focus_exited.connect(_on_panel_name_focus_exited)
	_name_edit.gui_input.connect(_on_panel_name_edit_gui_input)

# 收窄 LineEdit 默认主题里偏厚的上下边距，让它的高度贴近名字文字，
# 避免编辑时把所在的 HBox 整行撑高（否则同排的图标会被纵向拉长）。
func _apply_compact_lineedit_style(le: LineEdit) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.10)
	box.set_corner_radius_all(3)
	box.content_margin_left = 4
	box.content_margin_right = 4
	box.content_margin_top = 0
	box.content_margin_bottom = 0
	le.add_theme_stylebox_override("normal", box)
	le.add_theme_stylebox_override("focus", box)

func _start_panel_rename() -> void:
	if not is_instance_valid(current_employee) or _is_editing_name:
		return
	_is_editing_name = true
	_name_before_edit = current_employee.get_display_name()
	_name_edit.text = _name_before_edit
	_name_info_label.hide()
	_edit_name_button.hide()
	_name_edit.show()
	# 等控件显示后再抢焦点并全选，让玩家直接打字覆盖
	_name_edit.grab_focus.call_deferred()
	_name_edit.select_all.call_deferred()

func _on_panel_name_submitted(_text: String) -> void:
	_commit_panel_rename()

func _on_panel_name_focus_exited() -> void:
	_commit_panel_rename()

func _on_panel_name_edit_gui_input(event: InputEvent) -> void:
	# Esc 取消：先还原再退出，并吃掉事件防止冒泡
	if event.is_action_pressed("ui_cancel"):
		_cancel_panel_rename()
		accept_event()

func _commit_panel_rename() -> void:
	if not _is_editing_name:
		return
	_is_editing_name = false
	var new_name := _name_edit.text.strip_edges()
	# 空名字不接受 → 还原（不写回）；没变化也不写回
	if new_name != "" and is_instance_valid(current_employee) and new_name != current_employee.get_display_name():
		current_employee.set_custom_name(new_name)  # 写回数据源，display_name_changed 刷新所有视图
	_exit_panel_edit_mode()

func _cancel_panel_rename() -> void:
	if not _is_editing_name:
		return
	# 先置标志位，随后 hide() 触发的 focus_exited 会被 _commit_panel_rename 拦掉，绝不提交新文本
	_is_editing_name = false
	_name_edit.text = _name_before_edit
	_exit_panel_edit_mode()

func _exit_panel_edit_mode() -> void:
	_name_edit.hide()
	_name_info_label.show()
	_edit_name_button.show()
	if is_instance_valid(current_employee):
		name_label.set_value_text(current_employee.get_display_name())

# 语言切换时重刷三条属性 tooltip（tr 写死的不会自动刷新）
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		efficiency_bar.tooltip_text = tr("TOOLTIP_EMP_EFFICIENCY")
		quality_bar.tooltip_text = tr("TOOLTIP_EMP_QUALITY")
		experience_bar.tooltip_text = tr("TOOLTIP_EMP_EXPERIENCE")
		go_meeting_btn.tooltip_text = tr("TOOLTIP_GO_MEETING")
		attribute_label.tooltip_text = tr("EMP_TENURE")
		if current_employee:
			name_label.set_value_text(current_employee.get_display_name())
		_refresh_buffs()  # buff 标签是动态生成的，语言变了要重建一遍
		# 派遣按钮文字是动态的（派遣/召回），延迟覆盖以晚于 normal_button 自己的翻译刷新
		call_deferred("_update_dispatch_button")

# 在职时间 = 当前总游戏时长 − 入职时的游戏时长，仅面板可见时每帧刷新
func _process(_delta: float) -> void:
	if visible and is_instance_valid(current_employee):
		_update_tenure()
		_update_go_meeting_button()   # 会议室可能被填满/解散，实时刷新按钮可用状态

func _update_tenure() -> void:
	if not is_instance_valid(current_employee):
		return
	attribute_label.set_value_text(_format_tenure(Gamemanager.total_time - current_employee.hire_time))

# 格式化成 时:分:秒（小时不限位，超过一天就继续累加小时，够紧凑）
func _format_tenure(seconds: float) -> String:
	var s: int = int(max(seconds, 0.0))
	return "%02d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]

func _input(event: InputEvent) -> void:
	if is_locked_by_tutorial:
		return

	# 确认弹窗开着时，绝不做“点外面关闭”判定。
	# 弹窗按钮在 PanelBg 矩形之外（见场景里 PopupWindow 的 offset_left=-827），
	# 否则点确认会被当成“点到面板外”，在 confirmed 信号触发前就 close_panel() 把
	# current_employee 清空，导致 execute_fire_employee 跳过移除逻辑、开除失效。
	if popup_window and popup_window.visible:
		return

	# 只在鼠标左键【按下】的瞬间做拦截判定
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not visible: 
			return
		
		# 🌟 规则 1：点在面板自己身上？绝对不关！
		# 使用 get_global_mouse_position() 匹配 UI 坐标
		if _is_pos_inside_panel(get_global_mouse_position()):
			return
		
		# 🌟 规则 2：点在当前正看着的员工身上？绝对不关！
		# 利用员工自己的 2D 世界坐标系进行极其精准的碰撞检测
		if current_employee != null and is_instance_valid(current_employee) and current_employee.is_inside_tree():
			if current_employee.get_global_rect().has_point(current_employee.get_global_mouse_position()):
				return

		# 🌟 规则 3：既不是面板，也不是当前员工（比如点到了空地，或者另一个员工）
		# 干净利落地关闭！
		close_panel()
					
func open_panel(employee: Employee) -> void:
	if employee == null:
		return
	
	# 🌟 第一重保护：如果点的是同一个人，且面板开着，直接无视，不重刷信号也不播动画
	if visible and current_employee == employee:
		return
	
	# 换人前若正在改名，先把当前编辑提交掉（此时 current_employee 还是旧的，提交给对的人）
	if _is_editing_name:
		_commit_panel_rename()

	# 如果换了人，或者面板本来是关着的，才执行下面的刷新
	_disconnect_current_employee() # 换人前先把旧的断了
	current_employee = employee
	
	# ==========================================
	# 🚨 【这里是之前丢失的“三维”刷新代码】
	# ==========================================
	name_label.set_value_text(employee.get_display_name())
	
	# 刷新稀有度
	match employee.rarity:
		Employee.Rarity.R: 
			rarity_label.set_value_text("R")
		Employee.Rarity.SR: 
			rarity_label.set_value_text("SR")
		Employee.Rarity.SSR: 
			rarity_label.set_value_text("SSR")
	
	# 把“属性之和”改成“在职时间”（实时由 _process 刷新）
	attribute_label.tooltip_text = tr("EMP_TENURE")
	_update_tenure()
	
	# 🌟 刷新属性条（确保你的节点引用名和这里一致）
	efficiency_bar.set_value(employee.efficiency)
	quality_bar.set_value(employee.quality)
	experience_bar.set_value(employee.experience)
	
	# 顺便设置颜色（如果你需要的话）
	efficiency_bar.set_bar_color(Color.from_string("#4fb2ff", Color.BLUE))
	quality_bar.set_bar_color(Color.from_string("#eeb422", Color.YELLOW))
	experience_bar.set_bar_color(Color.from_string("#76c442", Color.GREEN))
	# ==========================================
	
	if employee.portrait:
		# 🌟 改成这一句：直接把立绘节点(figure)交给 Helper 处理
		AvatarHelper.apply_portrait(figure, employee.portrait, employee.rarity)
	
	_refresh_progress_bar()
	_refresh_buffs()
	_update_dispatch_button()
	_update_go_meeting_button()
	_connect_current_employee()
	
	# 🌟 第二重保护：只在面板还没出来时才播动画/show
	if not visible:
		show()
		# 如果你有入场动画，在这里播：$AnimationPlayer.play("fade_in")
	
	popup_window.hide() # 换人时把之前的弹窗藏了

func close_panel() -> void:
	# 关闭前若正在改名，先提交（点面板外关闭 = 点击别处提交）
	if _is_editing_name:
		_commit_panel_rename()
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
	if not current_employee.work_speed_up_triggered.is_connected(_play_speedup_vfx):
		current_employee.work_speed_up_triggered.connect(_play_speedup_vfx)
	if not current_employee.display_name_changed.is_connected(_on_current_employee_renamed):
		current_employee.display_name_changed.connect(_on_current_employee_renamed)

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
	if current_employee.work_speed_up_triggered.is_connected(_play_speedup_vfx):
		current_employee.work_speed_up_triggered.disconnect(_play_speedup_vfx)
	if current_employee.display_name_changed.is_connected(_on_current_employee_renamed):
		current_employee.display_name_changed.disconnect(_on_current_employee_renamed)
		
func _refresh_progress_bar() -> void:
	if current_employee == null:
		progress_bar.value = 0
		return

	var progress = current_employee.get_work_progress_percent()
	progress_bar.value = progress
	working_status.text = "%d%%" % progress

func _on_work_progress_changed(progress_percent: float) -> void:
	progress_bar.value = progress_percent
	working_status.text = "%d%%" % int(progress_percent)

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

# 当前查看的员工被改名时刷新名字标签
func _on_current_employee_renamed() -> void:
	if is_instance_valid(current_employee):
		name_label.set_value_text(current_employee.get_display_name())
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
		dispatch_btn_label.text = tr("WAREHOUSE_BULK_RECALL")
	else:
		dispatch_btn_label.text = tr("WAREHOUSE_BULK_DISPATCH")

# "去开会"按钮：不可用（没会议室/满员/不在工位/已在会）时禁用并置灰
func _update_go_meeting_button() -> void:
	if not is_instance_valid(go_meeting_btn):
		return
	var can := is_instance_valid(current_employee) \
		and current_employee.has_method("can_go_to_meeting") \
		and current_employee.can_go_to_meeting()
	go_meeting_btn.disabled = not can
	# 没有 disabled 贴图，用 modulate 手动置灰
	go_meeting_btn.modulate = Color(1, 1, 1, 1) if can else Color(0.55, 0.55, 0.55, 0.6)

func _on_go_meeting_pressed() -> void:
	if current_employee == null or not is_instance_valid(current_employee):
		return
	if not current_employee.has_method("go_to_meeting_directly"):
		return
	# 一键送会：员工顺移进会议室（无需拖拽）
	if current_employee.go_to_meeting_directly():
		# 成功进会后员工已隐身在会议室，关掉面板（与拖进会议室后的表现一致）
		close_panel()

func _on_dispatch_pressed() -> void:
	if current_employee == null: return
	
	if _is_employee_on_map():
		
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
		EmployeeManager.employee_map_status_changed.emit()
	else:
		if current_employee.get_parent():
			current_employee.get_parent().remove_child(current_employee)
		
		Gamemanager.request_employee_drop.emit(current_employee)
	
	# 刷新按钮文字
	_update_dispatch_button()
# ==========================================
# 6. 优化(开除)弹窗逻辑
# ==========================================
func _on_fire_pressed() -> void:
	# 把整个员工面板提到同级最后 = 输入命中最优先。
	# ⚠️ Godot 里 z_index 只改绘制顺序、不改输入命中顺序（输入按场景树同级顺序判定，
	#    越靠后越先接收点击）。弹窗虽然靠 z_index 画在最上层，但点击会被排在后面的
	#    RecruitmentPanel 抢走，导致点确认其实点到了背后的招聘面板、开除不执行。
	var p := get_parent()
	if p:
		p.move_child(self, p.get_child_count() - 1)

	# 在显示弹窗前，动态设置一下文本（利用你写的 set 属性）
	popup_window.title_text = tr("EMP_FIRE_TITLE").format({"name": current_employee.get_display_name()})
	popup_window.confirm_label = tr("WAREHOUSE_BULK_FIRE_CONFIRM")
	popup_window.cancel_label = tr("WAREHOUSE_BULK_FIRE_CANCEL")
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
		
		# 螺旋升天特效（销毁前用立绘造个幽灵来演）
		if current_employee.has_method("spawn_fire_ascend_effect"):
			current_employee.spawn_fire_ascend_effect()
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
	# 1. 每次打开面板前，先把旧的 Buff 标签清空
	for child in buffs_container.get_children():
		child.queue_free()
		
	if current_employee == null:
		return
		
	# ==========================================
	# 🌟 Meeting Buff
	# ==========================================
	if current_employee.is_in_meeting:
		var q_val = current_employee.meet_buff_qual
		var e_val = current_employee.meet_buff_exp
		var eff_val = current_employee.meet_buff_eff
		
		var details = tr("BUFF_MEETING_DESC").format({"q": q_val, "e": e_val, "eff": eff_val})
		_add_buff_label(tr("BUFF_MEETING_NAME"), details)
		
	# 2. Desk Buff (工位 Buff)
	if current_employee.get("current_seat") != null:
		var seat = current_employee.current_seat
		var eff_buff = 0
		var qual_buff = 0
		
		if seat.has_method("get_efficiency_buff"):
			eff_buff = seat.get_efficiency_buff()
		if seat.has_method("get_quality_buff"):
			qual_buff = seat.get_quality_buff()
			
		if eff_buff > 0 or qual_buff > 0:
			var desc = tr("BUFF_DESK_DESC_HEADER") + "\n"
			if eff_buff > 0: desc += tr("BUFF_DESK_EFF").format({"v": eff_buff}) + " "
			if qual_buff > 0: desc += tr("BUFF_DESK_QUAL").format({"v": qual_buff})
			_add_buff_label(tr("BUFF_DESK_NAME"), desc)
			
	# 3. Culture Buff (企业文化 Buff)
	if OfficeManager.culture_efficiency > 0:
		_add_buff_label(tr("BUFF_CULTURE_NAME"), tr("BUFF_CULTURE_EFF").format({"v": OfficeManager.culture_efficiency}))
	if OfficeManager.culture_experience > 0:
		_add_buff_label(tr("BUFF_CULTURE_NAME"), tr("BUFF_CULTURE_EXP").format({"v": OfficeManager.culture_experience}))
	if OfficeManager.culture_quality > 0:
		_add_buff_label(tr("BUFF_CULTURE_NAME"), tr("BUFF_CULTURE_QUAL").format({"v": OfficeManager.culture_quality}))
		
	# 4. Snack Buff (零食 Buff)
	if current_employee.get("current_snack_buff") != null:
		var snack = int(current_employee.get("current_snack_buff"))
	
		
		match snack:
			1: # Milk Tea 奶茶
				_add_buff_label(tr("BUFF_SNACK_MILKTEA"), tr("BUFF_SNACK_MILKTEA_DESC"))
			2: # Cake 蛋糕
				_add_buff_label(tr("BUFF_SNACK_CAKE"), tr("BUFF_SNACK_CAKE_DESC"))
			3: # Sausage 烤肠
				_add_buff_label(tr("BUFF_SNACK_SAUSAGE"), tr("BUFF_SNACK_SAUSAGE_DESC"))

func _add_buff_label(buff_name: String, hover_description: String) -> void:
	var buff_tag = BUFF_TAG_SCENE.instantiate()
	buff_tag.add_to_group("buffs")
	var label_node = buff_tag.get_node("%Label")
	label_node.text = "✦ " + buff_name
	
	buff_tag.tooltip_text = hover_description
	
	if is_locked_by_tutorial:
		buff_tag.mouse_filter = Control.MOUSE_FILTER_PASS
	else:
		buff_tag.mouse_filter = Control.MOUSE_FILTER_STOP
		
	buffs_container.add_child(buff_tag)

func _is_pos_inside_panel(global_pos: Vector2) -> bool:
	# 面板可见区域 = 主体 PanelBg + 顶部 TitleBar（TitleBar 是 PanelBg 的同级节点，
	# 不在 PanelBg 矩形内，所以必须单独判定，否则点 titlebar 会被当成“点到面板外”而关闭）
	if $PanelBg.get_global_rect().has_point(global_pos):
		return true
	if title_bar and title_bar.get_global_rect().has_point(global_pos):
		return true
	return false

#func _is_pos_on_any_employee(global_pos: Vector2) -> bool:
	## 遍历所有在 "employees" 组里的节点
	#var all_employees = get_tree().get_nodes_in_group("employees")
	#for emp in all_employees:
		#if emp is Control:
			## 检查鼠标位置是否在员工的矩形范围内
			#if emp.get_global_rect().has_point(global_pos):
				#return true
	#return false

func force_bind_and_refresh(employee: Employee) -> void:
	current_employee = employee
	
	# 强制将引用传递给每一个子组件，哪怕它们之前是空的
	if employee:
		# 1. 刷新基础信息
		name_label.set_value_text(employee.get_display_name())
		# 2. 刷新进度条
		_refresh_progress_bar()
		# 3. 刷新 Buffs
		_refresh_buffs()
		# 4. 刷新立绘
		if employee.portrait:
			AvatarHelper.apply_portrait(figure, employee.portrait, employee.rarity)
		
		show()

func _play_speedup_vfx() -> void:
	if _shake_tween:
		_shake_tween.kill()
		
	# 还原所有初始状态
	progress_bar.position = Vector2.ZERO 
	progress_bar.scale = Vector2.ONE
	working_status.modulate = Color.WHITE # 确保初始是白色
	
	if fire_vfx:
		fire_vfx.show()
		
	_shake_tween = create_tween()
	
	# 🌟 核心：在变大变红的同时进行
	_shake_tween.set_parallel(true)
	
	# 进度条变大 (保持你之前的逻辑)
	_shake_tween.tween_property(progress_bar, "scale", Vector2(1.1, 1.1), 0.05).set_ease(Tween.EASE_OUT)
	
	# 🌟 字体瞬间变红 (Color.RED)
	_shake_tween.tween_property(working_status, "modulate", Color.RED, 0.05)
	
	_shake_tween.set_parallel(false) # 后面的震动逻辑串行执行
	
	# 连续高频随机震动
	for i in range(4):
		var random_offset = Vector2(randf_range(-3, 3), randf_range(-3, 3))
		_shake_tween.tween_property(progress_bar, "position", random_offset, 0.03)
		
	# 恢复原状
	_shake_tween.set_parallel(true) # 同时恢复颜色和位置
	_shake_tween.tween_property(progress_bar, "position", Vector2.ZERO, 0.03)
	_shake_tween.tween_property(progress_bar, "scale", Vector2.ONE, 0.1).set_ease(Tween.EASE_IN_OUT)
	
	# 🌟 字体恢复白色 (回到原来的状态)
	_shake_tween.tween_property(working_status, "modulate", Color.WHITE, 0.1)
	
	_shake_tween.set_parallel(false)
	
	# 动画完全结束后灭掉火苗
	_shake_tween.tween_callback(func():
		if fire_vfx: fire_vfx.hide()
	)


func _on_title_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			drag_offset = get_global_mouse_position() - global_position

	if event is InputEventMouseMotion and dragging:
		var target: Vector2 = get_global_mouse_position() - drag_offset
		var vp := get_viewport_rect().size
		# 限制在游戏窗口内：拖到边缘就停，不能跑出窗口外变半透明
		target.x = clampf(target.x, 0.0, maxf(0.0, vp.x - size.x))
		target.y = clampf(target.y, 0.0, maxf(0.0, vp.y - size.y))
		global_position = target
