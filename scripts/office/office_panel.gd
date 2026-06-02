#office_panel.gd
extends Control

# 用于保存当前正在操作的那个办公室实例
var current_target_office: Office = null

# 🌟 新增：引用面板的底图，用于判断鼠标是不是点在它外面
@onready var background: NinePatchRect = $bcg
@onready var tab_container: TabContainer = $TabContainer

# 🌟 新增：记录打开面板的时间，防止当前帧点击误触发关闭
var _open_time: int = 0
var is_locked: bool = false

func lock_for_tutorial():
	is_locked = true
	show() # 强制显形

func unlock_from_tutorial():
	is_locked = false


# 这里的路径请根据你实际的节点树修改
# --- 引用原有的容器 ---
@onready var selection_page: Control = $TabContainer/Office
@onready var culture_page: Control = $TabContainer/Culture

# --- 按钮容器引用 ---
@onready var selection_buttons: GridContainer = $TabContainer/Office/OfficeButton
var culture_buttons: VBoxContainer
var dragging = false
var drag_offset = Vector2()

func _ready() -> void:
	
	hide()
# 🌟 2. 核心魔法：去 culture_page 内部向下搜索名为 "VBoxContainer" 的节点
	# 参数 true 表示向下无限层级搜索，参数 false 表示无视场景的所有权（强行掏出子场景的节点）
	culture_buttons = culture_page.find_child("VBoxContainer", true, false)
	
	# 检查一下有没有找到，防止报错
	if culture_buttons == null:
		print("⚠️ 没在 Culture 场景里找到 VBoxContainer！请检查子场景内部节点名字。")
	
	_setup_selection_buttons()
	_setup_culture_buttons()

# 🌟 新增：核心交互逻辑 - 检测区域外点击
func _input(event: InputEvent) -> void:
	# 只有面板显示时才检测
	if not visible:
		return
	if is_locked:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# 保护：如果是刚刚打开面板（同一帧或 0.1 秒内），不执行关闭
			if Time.get_ticks_msec() - _open_time < 100:
				return
				
			# 判定：如果点击位置不在 background 的矩形区域内
			var mouse_pos = get_global_mouse_position()
			if not background.get_global_rect().has_point(mouse_pos):
				close_panel()

func open_panel(office: Node, open_culture_tab: bool = false) -> void:
	current_target_office = office
	_open_time = Time.get_ticks_msec()
	
	var is_culture_center = (office.current_type == Gamemanager.OfficeType.CULTURE_CENTER)
	
	tab_container.set_tab_hidden(1, !is_culture_center) 
	
	if open_culture_tab and is_culture_center:
		tab_container.current_tab = 1
	else:
		tab_container.current_tab = 0

	# 每次打开面板，直接全场广播刷新
	_refresh_all_ui()
	
	show()

func _refresh_all_ui() -> void:
	if not current_target_office: return
	
	# 刷新第一页的办公室按钮
	get_tree().call_group("office_buttons", "refresh_status", current_target_office)
	
	var is_culture = (current_target_office.current_type == Gamemanager.OfficeType.CULTURE_CENTER)
	if culture_buttons:
		culture_buttons.visible = is_culture
		
func _setup_selection_buttons() -> void:
	for child in selection_buttons.get_children():
		if child is Button:
			child.pressed.connect(_on_selection_clicked.bind(child))

func _setup_culture_buttons() -> void:
	if not culture_buttons: return
	
	var actual_buttons = []
	for child in culture_buttons.get_children():
		if child is Button:
			actual_buttons.append(child)
			
	if actual_buttons.size() >= 3:
		actual_buttons[0].pressed.connect(_on_culture_selected.bind(CultureCenterLogic.CultureType.EFF_UP))
		actual_buttons[1].pressed.connect(_on_culture_selected.bind(CultureCenterLogic.CultureType.QUAL_UP))
		actual_buttons[2].pressed.connect(_on_culture_selected.bind(CultureCenterLogic.CultureType.EXP_UP))

func _on_selection_clicked(button_node: Node) -> void:
	if not current_target_office: return
	var new_type = button_node.office_type
	current_target_office.change_function(new_type)
	close_panel()

func _on_culture_selected(type: CultureCenterLogic.CultureType) -> void:
	# 从 Office 实例中找到逻辑组件
	if current_target_office and current_target_office.logic_node is CultureCenterLogic:
		current_target_office.logic_node.switch_culture(type)
	_refresh_culture_highlight()
	#close_panel()

func _refresh_selection_state() -> void:
	for child in selection_buttons.get_children():
		# 🌟 核心魔法：如果子节点有 refresh_status 这个函数，就执行它
		if child.has_method("refresh_status"):
			child.refresh_status(current_target_office)
			
			# 针对“唯一性”在面板层级的特殊修正（可选）：
			# 如果该按钮代表的功能正是当前办公室的功能，应该让它亮起来，方便玩家切换回来
			if child.office_type == current_target_office.current_type:
				child.disabled = false
				child.modulate = Color(1.2, 1.2, 1.2, 1.0) # 稍微高亮表示当前选中

# 🌟 统一关闭函数，清理引用
func close_panel() -> void:
	current_target_office = null
	hide()

func on_type_selected(new_type: Gamemanager.OfficeType) -> void:
	if current_target_office == null:
		return
	current_target_office.change_function(new_type)
	close_panel()

func _refresh_culture_highlight() -> void:
	if not current_target_office or not current_target_office.logic_node is CultureCenterLogic:
		return
	
	var current_policy = current_target_office.logic_node.cur_type
	var btns = culture_buttons.get_children()

	for btn in btns:
		if not btn is Button: continue
		
		# 🌟 核心逻辑：根据按钮名字来判断它代表哪个枚举
		# 请根据你编辑器里按钮的真实名字修改下面的字符串
		var btn_type = -1
		if "Eff" in btn.name:
			btn_type = CultureCenterLogic.CultureType.EFF_UP
		elif "Qual" in btn.name:
			btn_type = CultureCenterLogic.CultureType.QUAL_UP
		elif "Exp" in btn.name:
			btn_type = CultureCenterLogic.CultureType.EXP_UP
		
		# 🌟 涂色：如果这个按钮代表的类型 == 当前政策，就亮
		if btn_type == current_policy:
			btn.modulate = Color(1.5, 1.5, 0.5, 1.0) # 高亮
		else:
			btn.modulate = Color(1.0, 1.0, 1.0, 0.5) # 暗示未选中

func _on_title_bar_gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			drag_offset = get_global_mouse_position() - global_position
			
	if event is InputEventMouseMotion and dragging:
		global_position = get_global_mouse_position() - drag_offset


func _on_close_panel_pressed() -> void:
	if is_locked: return
	self.hide()
