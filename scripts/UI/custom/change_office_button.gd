# change_office_button.gd
extends TextureButton # 如果你的根节点是普通的 Button，请改为 extends Button

# --- 在 Inspector 中配置的参数 ---
@export_group("Settings")
@export var office_type: Gamemanager.OfficeType = Gamemanager.OfficeType.NONE
@export var button_text: String = ""

@export_group("Visuals")
@export var normal_icon: Texture2D # 按钮的常规图标

# 引用子节点
@onready var label: Label = $Label

func _ready() -> void:
	# 1. 初始化文字显示
	if label:
		label.text = button_text
		# 确保 Label 不会拦截鼠标点击，否则按钮点不到
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# 2. 初始化图标显示 (针对 TextureButton)
	if normal_icon:
		texture_normal = normal_icon
	
	# 3. 连接点击信号
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	# 不要只传名字，直接传我们配置好的 type
	var panel = get_tree().get_first_node_in_group("office_panel")
	if panel:
		# 这里我们调用面板的一个新函数，直接传类型
		panel.on_type_selected(office_type)
