#office_panel.gd
extends Control

# 用于保存当前正在操作的那个办公室实例
var current_target_office: Office = null

# 🌟 新增：引用面板的底图，用于判断鼠标是不是点在它外面
@onready var background: TextureRect = $Background 
@onready var tab_container: TabContainer = $Background/TabContainer

# 🌟 新增：记录打开面板的时间，防止当前帧点击误触发关闭
var _open_time: int = 0

# 这里的路径请根据你实际的节点树修改
# --- 引用原有的容器 ---
@onready var selection_page: Control = $Background/TabContainer/Office
@onready var culture_page: Control = $Background/TabContainer/Culture

# --- 按钮容器引用 ---
@onready var selection_buttons: VBoxContainer = $Background/TabContainer/Office/VBoxContainer
var culture_buttons: VBoxContainer

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
		
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# 保护：如果是刚刚打开面板（同一帧或 0.1 秒内），不执行关闭
			if Time.get_ticks_msec() - _open_time < 100:
				return
				
			# 判定：如果点击位置不在 background 的矩形区域内
			var mouse_pos = get_global_mouse_position()
			if not background.get_global_rect().has_point(mouse_pos):
				close_panel()
				# 如果你不希望点击到外面的办公室，可以取消下面这行的注释：
				# get_viewport().set_input_as_handled()

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
		print("[OfficePanel] 已下发新政策: ", type)
	_refresh_culture_highlight()
	#close_panel()

func open_panel(office: Office, open_culture_tab: bool = false) -> void:
	# 1. 记录初始状态
	var was_hidden = !visible
	current_target_office = office
	_open_time = Time.get_ticks_msec()
	
	# 2. 判定类型
	var is_culture_center = (office.current_type == Gamemanager.OfficeType.CULTURE_CENTER)
	
	# 3. 先处理显隐（这步最危险，可能导致索引重置）
	# 我们显式地先把两页都打开，防止跳转失败，然后再根据类型隐藏
	tab_container.set_tab_hidden(0, false)
	tab_container.set_tab_hidden(1, false) # 先全部释放，让索引 1 处于合法状态
	
	# 4. 执行跳转逻辑（核心修正点）
	if open_culture_tab and is_culture_center:
		# 如果明确要求去文化页，直接强制赋值
		tab_container.current_tab = 1
	elif was_hidden:
		# 只有从关闭状态打开，且没要求去文化页，才去第一页
		tab_container.current_tab = 0
	# else: 面板本来就开着时，我们完全不去碰 current_tab 变量！
	
	# 5. 最后再根据实际情况隐藏第二页
	# 如果当前就在第一页且不是文化中心，才隐藏老二
	if not is_culture_center:
		tab_container.set_tab_hidden(1, true)

	# 6. 刷新内容
	_refresh_selection_state()
	_refresh_culture_highlight()
	
	show()
	print("面板最终停留在页签：", tab_container.current_tab, " | 来自点击要求：", open_culture_tab)
# 提取出来的刷新逻辑，方便调用
func _refresh_selection_state() -> void:
	for child in selection_buttons.get_children():
		if not "office_type" in child:
			continue
		child.disabled = false
		child.modulate = Color(1, 1, 1, 1)
		
		var type_to_check = child.office_type
		var already_exists = false
		if type_to_check == Gamemanager.OfficeType.RECRUITMENT:
			already_exists = OfficeManager.has_recruitment_office
		elif type_to_check == Gamemanager.OfficeType.CULTURE_CENTER:
			already_exists = OfficeManager.has_culture_center
		
		if already_exists and current_target_office.current_type != type_to_check:
			child.disabled = true
			child.modulate = Color(0.3, 0.3, 0.3, 1)

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
