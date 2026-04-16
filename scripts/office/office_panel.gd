extends Control

# 用于保存当前正在操作的那个办公室实例
var current_target_office: Office = null

# 这里的路径请根据你实际的节点树修改
# 假设你的按钮都在 VBoxContainer 下
@onready var buttons_container: VBoxContainer = $Background/MarginContainer/VBoxContainer

func _ready() -> void:
	# 1. 初始状态先隐藏自己
	hide()
	
	# 2. 自动连接目录下所有按钮的信号
	# 这样你就不用一个一个去编辑器里连信号了
	_setup_buttons()

func _setup_buttons() -> void:
	for child in buttons_container.get_children():
		# 确保这个 child 确实是我们那个带脚本的按钮
		if child.has_method("_on_pressed"): # 或者 if child is ChangeOfficeButton
			# 核心修改：直接连接按钮点击，不需要 bind 名字了
			# 我们可以让按钮自己处理点击，面板只负责“收听”
			if not child.pressed.is_connected(_on_button_clicked):
				# 我们把 child 传过去，这样就能拿到它身上的 office_type
				child.pressed.connect(_on_button_clicked.bind(child))

# 新的统一处理函数
func _on_button_clicked(button_node: Node) -> void:
	if current_target_office == null:
		return
		
	# 直接从按钮节点身上拿你在 Inspector 里选好的那个 type
	var new_type = button_node.office_type
	
	# 如果点的是取消（假设你给取消按钮配的 type 是 NONE）
	if new_type == Gamemanager.OfficeType.NONE and "Cancel" in button_node.name:
		hide()
		return
		
	# 直接调用切换
	current_target_office.change_function(new_type)
	hide()

func open_panel(office: Office) -> void:
	current_target_office = office
	show()
	
	for child in buttons_container.get_children():
		# 确保是我们要处理的按钮脚本
		if not "office_type" in child:
			continue
			
		# 1. 默认状态：先全部解禁，恢复亮度
		child.disabled = false
		child.modulate = Color(1, 1, 1, 1)
		
		# 2. 核心判定：只针对“全场唯一”的类型进行检查
		var type_to_check = child.office_type
		var already_exists = false
		
		if type_to_check == Gamemanager.OfficeType.RECRUITMENT:
			already_exists = OfficeManager.has_recruitment_office
		elif type_to_check == Gamemanager.OfficeType.BULLETIN_BOARD:
			already_exists = OfficeManager.has_bulletin_board
		
		# 3. 执行禁用：
		# 如果该功能已在全场存在，且【当前点击的办公室】并不是正在担任这个功能的那个
		if already_exists and current_target_office.current_type != type_to_check:
			child.disabled = true
			child.modulate = Color(0.3, 0.3, 0.3, 1) # 变灰
			print("禁用按钮: ", child.name, " 因为唯一建筑 ", type_to_check, " 已存在")
		
func on_type_selected(new_type: Gamemanager.OfficeType) -> void:
	if current_target_office == null:
		return
	
	# 既然类型已经是匹配好的枚举，直接传给办公室就行！
	current_target_office.change_function(new_type)
	
	# 操作完隐藏面板
	hide()
	
# 点击面板以外或者点击关闭按钮时可以手动调用
func close_panel() -> void:
	current_target_office = null
	hide()
