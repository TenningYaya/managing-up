extends HBoxContainer

const MIN_BUBBLE_WIDTH := 140.0
const MAX_BUBBLE_WIDTH := 700.0

@onready var bubble_patch: NinePatchRect = $BubblePatch
@onready var bubble_padding: MarginContainer = $BubblePatch/BubblePadding
@onready var bubble_label: Label = $BubblePatch/BubblePadding/BubbleLabel

func setup(dialogue_text: String) -> void:
	alignment = BoxContainer.ALIGNMENT_BEGIN
	bubble_label.add_theme_color_override("font_color", Color.WHITE)
	bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	set_dialogue_text(dialogue_text)

func set_dialogue_text(dialogue_text: String) -> void:
	bubble_label.text = dialogue_text
	_update_bubble_size(dialogue_text)

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

	# 只限制宽度，高度设为 0 让气泡根据文字内容自动撑高
	bubble_patch.custom_minimum_size.x = target_width
	bubble_patch.custom_minimum_size.y = 0

	bubble_label.custom_minimum_size.x = target_width - padding_left - padding_right
	bubble_label.custom_minimum_size.y = 0
