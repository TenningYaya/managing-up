extends HBoxContainer

# 请将这里的路径改成你项目中“图三”所在的实际路径
# 注意：图三是 jpg 格式，自带黑色背景。如果你的游戏背景不是全黑的，建议用修图软件把黑色背景抠掉，另存为透明背景的 png 图片。
const BUBBLE_TEXTURE: Texture2D = preload("res://assets/dialogue/buss_bubble_green.png")

const MIN_BUBBLE_WIDTH := 140.0
const MAX_BUBBLE_WIDTH := 520.0

@onready var bubble_panel: PanelContainer = $BubblePanel
@onready var bubble_padding: MarginContainer = $BubblePanel/BubblePadding
@onready var bubble_label: Label = $BubblePanel/BubblePadding/BubbleLabel

# 取消了 speaker 参数，因为现在只有 Boss
func setup(dialogue_text: String) -> void:
	# 气泡靠左对齐
	alignment = BoxContainer.ALIGNMENT_BEGIN
	
	# 设置字体颜色（绿色气泡配黑色或白色都可以，这里默认用白色）
	bubble_label.add_theme_color_override("font_color", Color.WHITE)
	
	_apply_bubble_texture(BUBBLE_TEXTURE)
	
	set_dialogue_text(dialogue_text)

func set_dialogue_text(dialogue_text: String) -> void:
	bubble_label.text = dialogue_text
	_update_bubble_size(dialogue_text)

func _apply_bubble_texture(texture: Texture2D) -> void:
	var style := StyleBoxTexture.new()
	style.texture = texture
	
	# 设置 Texture Margin，保护四周边缘不发生变形
	# 你可以稍微修改这些数字，看看什么效果最好
	style.texture_margin_left = 80.0   # 保护左边的小尾巴和圆角
	style.texture_margin_right = 80.0  # 保护右边的圆角
	style.texture_margin_top = 20.0    # 保护上面的圆角
	style.texture_margin_bottom = 20.0 # 保护下面的圆角
	
	bubble_panel.add_theme_stylebox_override("panel", style)
	
	
func _update_bubble_size(dialogue_text: String) -> void:
	var font := bubble_label.get_theme_font("font")
	var font_size := bubble_label.get_theme_font_size("font_size")

	var text_width := font.get_string_size(
		dialogue_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size
	).x

	var padding_left := bubble_padding.get_theme_constant("margin_left")
	var padding_right := bubble_padding.get_theme_constant("margin_right")

	var target_width := text_width + padding_left + padding_right

	target_width = clamp(target_width, MIN_BUBBLE_WIDTH, MAX_BUBBLE_WIDTH)

	bubble_panel.custom_minimum_size.x = target_width
	bubble_panel.custom_minimum_size.y = 0

	bubble_label.custom_minimum_size.x = target_width - padding_left - padding_right
	bubble_label.custom_minimum_size.y = 0
