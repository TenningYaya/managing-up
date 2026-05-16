extends HBoxContainer

const BOSS_BUBBLE_TEXTURE: Texture2D = preload("res://assets/dialogue/bubble_boss.png")
const EMPLOYEE_BUBBLE_TEXTURE: Texture2D = preload("res://assets/dialogue/bubble_employee.png")

const MIN_BUBBLE_WIDTH := 140.0
const MAX_BUBBLE_WIDTH := 520.0

@onready var bubble_panel: PanelContainer = $BubblePanel
@onready var bubble_padding: MarginContainer = $BubblePanel/BubblePadding
@onready var bubble_label: Label = $BubblePanel/BubblePadding/BubbleLabel


func setup(speaker: String, dialogue_text: String) -> void:
	if speaker == "boss":
		_set_boss_style()
	elif speaker == "employee":
		_set_employee_style()
	else:
		_set_boss_style()

	set_dialogue_text(dialogue_text)


func set_dialogue_text(dialogue_text: String) -> void:
	bubble_label.text = dialogue_text
	_update_bubble_size(dialogue_text)


func type_dialogue_text(full_text: String, char_delay: float = 0.035) -> void:
	# 先按照完整句子计算气泡大小，避免气泡一边打字一边变宽
	_update_bubble_size(full_text)

	# 先清空文字
	bubble_label.text = ""

	# 一个字母一个字母显示
	for i in range(1, full_text.length() + 1):
		bubble_label.text = full_text.substr(0, i)
		await get_tree().create_timer(char_delay).timeout

func _set_boss_style() -> void:
	# Boss 靠左
	alignment = BoxContainer.ALIGNMENT_BEGIN

	# 白色气泡，黑字
	bubble_label.add_theme_color_override("font_color", Color("#111111"))


	_apply_bubble_texture(BOSS_BUBBLE_TEXTURE)


func _set_employee_style() -> void:
	# Employee 靠右
	alignment = BoxContainer.ALIGNMENT_END

	# 绿色气泡，白字
	bubble_label.add_theme_color_override("font_color", Color.WHITE)


	_apply_bubble_texture(EMPLOYEE_BUBBLE_TEXTURE)


func _apply_bubble_texture(texture: Texture2D) -> void:
	var style := StyleBoxTexture.new()
	style.texture = texture

	bubble_panel.add_theme_stylebox_override("panel", style)


func _update_bubble_size(dialogue_text: String) -> void:
	var font := bubble_label.get_theme_font("font")
	var font_size := bubble_label.get_theme_font_size("font_size")

	# 计算文字本身大概需要多宽
	var text_width := font.get_string_size(
		dialogue_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size
	).x

	var padding_left := bubble_padding.get_theme_constant("margin_left")
	var padding_right := bubble_padding.get_theme_constant("margin_right")

	var target_width := text_width + padding_left + padding_right

	# 限制最小和最大宽度
	target_width = clamp(target_width, MIN_BUBBLE_WIDTH, MAX_BUBBLE_WIDTH)

	# 设置整个气泡宽度
	bubble_panel.custom_minimum_size.x = target_width
	bubble_panel.custom_minimum_size.y = 0

	# 设置文字区域宽度，让长句自动换行
	bubble_label.custom_minimum_size.x = target_width - padding_left - padding_right
	bubble_label.custom_minimum_size.y = 0
