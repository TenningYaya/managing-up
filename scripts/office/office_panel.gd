extends Control

# 用于保存当前正在操作的那个办公室实例
var current_target_office: Office = null

# 🌟 新增：引用面板的底图，用于判断鼠标是不是点在它外面
@onready var background: TextureRect = $Background 

# 🌟 新增：记录打开面板的时间，防止当前帧点击误触发关闭
var _open_time: int = 0

# 这里的路径请根据你实际的节点树修改
@onready var buttons_container: VBoxContainer = $Background/MarginContainer/VBoxContainer


func _ready() -> void:
	hide()
	_setup_buttons()

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
				print("[OfficePanel] 点击了外部，自动关闭")
				close_panel()
				# 如果你不希望点击到外面的办公室，可以取消下面这行的注释：
				# get_viewport().set_input_as_handled()

func _setup_buttons() -> void:
	for child in buttons_container.get_children():
		if child.has_method("_on_pressed"):
			if not child.pressed.is_connected(_on_button_clicked):
				child.pressed.connect(_on_button_clicked.bind(child))

func _on_button_clicked(button_node: Node) -> void:
	if current_target_office == null:
		return
		
	var new_type = button_node.office_type
	
	if new_type == Gamemanager.OfficeType.NONE and "Cancel" in button_node.name:
		close_panel() # 统一调用 close_panel
		return
		
	current_target_office.change_function(new_type)
	close_panel() # 统一调用 close_panel

func open_panel(office: Office) -> void:
	current_target_office = office
	
	# 🌟 记录打开瞬间的时间点
	_open_time = Time.get_ticks_msec()
	
	# 刷新按钮禁用状态
	_refresh_buttons()
	
	show()

# 提取出来的刷新逻辑，方便调用
func _refresh_buttons() -> void:
	for child in buttons_container.get_children():
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

# 这个函数目前与 _on_button_clicked 功能重复，可以根据需要保留或删除
func on_type_selected(new_type: Gamemanager.OfficeType) -> void:
	if current_target_office == null:
		return
	current_target_office.change_function(new_type)
	close_panel()
