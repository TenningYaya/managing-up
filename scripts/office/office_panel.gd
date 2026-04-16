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
	
	print("面板识别到按钮配置类型: ", new_type)
	
	# 如果点的是取消（假设你给取消按钮配的 type 是 NONE）
	if new_type == Gamemanager.OfficeType.NONE and "Cancel" in button_node.name:
		hide()
		return
		
	# 直接调用切换
	current_target_office.change_function(new_type)
	hide()

## --- 核心：被 Office.gd 通过 call_group 调用 ---
func open_panel(office: Office) -> void:
	# 记录是谁叫我打开的
	current_target_office = office
	
	# 显示面板
	show()
	
	# 这里的逻辑可以扩展：比如根据办公室当前功能，让对应的按钮变成高亮状态
	print("面板已打开，正在配置: ", office.name, " 当前功能: ", office.current_type)

## --- 按钮点击处理 ---
#func _on_any_function_button_pressed(btn_name: String) -> void:
	#if current_target_office == null:
		#return
	#
	## 根据按钮的名字来匹配 Gamemanager 里的枚举类型
	## 注意：这里的名字要和你场景树里按钮的名字对上
	#var new_type = Gamemanager.OfficeType.NONE
	#
	#if "Pantry" in btn_name:
		#new_type = Gamemanager.OfficeType.PANTRY
	#elif "Meeting" in btn_name:
		#new_type = Gamemanager.OfficeType.MEETING_ROOM
	#elif "Recruit" in btn_name:
		#new_type = Gamemanager.OfficeType.RECRUITMENT
	#elif "Bulletin" in btn_name:
		#new_type = Gamemanager.OfficeType.BULLETIN_BOARD
	#elif "Cancel" in btn_name:
		## 如果是取消按钮，直接隐藏面板即可
		#hide()
		#return
#
	## 调用办公室的切换功能函数
	#current_target_office.change_function(new_type)
	#
	## 切换完功能后，通常会关闭面板
	#hide()

func on_type_selected(new_type: Gamemanager.OfficeType) -> void:
	if current_target_office == null:
		return
		
	print("面板收到类型选择信号，类型编号: ", new_type)
	
	# 既然类型已经是匹配好的枚举，直接传给办公室就行！
	current_target_office.change_function(new_type)
	
	# 操作完隐藏面板
	hide()
	
# 点击面板以外或者点击关闭按钮时可以手动调用
func close_panel() -> void:
	current_target_office = null
	hide()
