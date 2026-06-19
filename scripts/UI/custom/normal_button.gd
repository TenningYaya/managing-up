#normal_button.gd
extends TextureButton

@export var button_text: String = "InputButtonName":
	set(value):
		button_text = value
		# 🌟 只要节点存在，就尝试翻译并赋值
		if is_inside_tree() and has_node("Label"):
			# tr() 如果找不到对应 key，就会原样返回 button_text 本身，完美符合你的要求！
			$Label.text = tr(button_text)

# 🌟 新增：我们自己开两个图片插槽，取代自带的 Textures
@export_group("NinePatch Background")
@export var bg_normal: Texture2D
@export var bg_pressed: Texture2D

@onready var bg_rect: NinePatchRect = $NinePatchRect

func _ready() -> void:
	if has_node("Label"):
		$Label.text = tr(button_text)
		
	# 初始状态显示 Normal 图片
	if bg_normal:
		bg_rect.texture = bg_normal
		
	# 🌟 核心魔法：监听按钮自己的点击信号，来偷换 NinePatchRect 的图片
	button_down.connect(_on_btn_down)
	button_up.connect(_on_btn_up)
	mouse_exited.connect(_on_btn_up) # 防止鼠标按住移出按钮时卡在按下状态

# 语言切换时重新翻译按钮文字（tr 写死的不会自动刷新）
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and has_node("Label"):
		$Label.text = tr(button_text)

func _on_btn_down() -> void:
	if not disabled and bg_pressed:
		bg_rect.texture = bg_pressed

func _on_btn_up() -> void:
	if not disabled and bg_normal:
		bg_rect.texture = bg_normal
