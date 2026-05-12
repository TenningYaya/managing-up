# culture_panel.gd
extends Control
class_name CulturePanel

# ==========================================
# 1. 节点引用 (请确保对应你的 Scene 树层级)
# ==========================================

# 假设你把三个按钮放在了一个 VBoxContainer 里
@onready var eff_btn: TextureButton = $MarginContainer/VBoxContainer/Eff
@onready var qual_btn: TextureButton = $MarginContainer/VBoxContainer/Qual
@onready var exp_btn: TextureButton =  $MarginContainer/VBoxContainer/Exp

# (可选) 如果你做了关闭按钮
#@onready var close_btn: Button = $PanelBg/CloseButton 

# 当前正在操作的办公室逻辑引用
var linked_logic: CultureCenterLogic = null

# ==========================================
# 2. 初始化
# ==========================================
func _ready() -> void:
	# 绑定点击外部遮罩关闭面
	
	# 🚨 【核心魔法】：使用 .bind() 直接把枚举值绑到点击信号上
	eff_btn.pressed.connect(_on_culture_selected.bind(CultureCenterLogic.CultureType.EFF_UP))
	qual_btn.pressed.connect(_on_culture_selected.bind(CultureCenterLogic.CultureType.QUAL_UP))
	exp_btn.pressed.connect(_on_culture_selected.bind(CultureCenterLogic.CultureType.EXP_UP))

# ==========================================
# 3. 打开与关闭逻辑
# ==========================================
func open_panel(logic_ref: CultureCenterLogic) -> void:
	if logic_ref == null: return
	
	linked_logic = logic_ref
	show()
	print("[CulturePanel] 打开了面板，准备洗脑！")

func close_panel() -> void:
	hide()
	linked_logic = null

func _on_click_blocker_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_panel()

# ==========================================
# 4. 业务逻辑：切换 Buff
# ==========================================
func _on_culture_selected(type: CultureCenterLogic.CultureType) -> void:
	if linked_logic:
		# 直接调用办公室组件里的切换函数
		linked_logic.switch_culture(type)
		print("[CulturePanel] 已下发新政策，类型: ", type)
	
	# 政策下发完毕，老板深藏功与名，自动关闭面板
	close_panel()

func setup(logic_ref: CultureCenterLogic) -> void:
	open_panel(logic_ref)
