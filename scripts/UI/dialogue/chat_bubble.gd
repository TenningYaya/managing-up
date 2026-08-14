extends HBoxContainer

const MIN_BUBBLE_WIDTH := 140.0
const MAX_BUBBLE_WIDTH := 700.0
# 气泡最小高度（≈ 九宫格上下 patch 边距之和），短消息保持现在的样子；
# 文字多了就按内容撑得更高。BubbleLabel 垂直居中，所以文字始终在气泡中间。
const MIN_BUBBLE_HEIGHT := 154.0
# 文字之外再额外上下各留的空，让气泡比文字大一圈（配合 padding 一起，避免顶到边）
const BUBBLE_V_EXTRA := 20.0
# 气泡底部再多留的空：bubble.png 底部是圆角，几何居中时最后一行看着会顶到圆角，
# 所以把底部 padding 调大一点，把文字整体往上顶、下方更宽松。
const BUBBLE_PAD_BOTTOM := 48

# 气泡最大宽度：超过就自动换行。默认沿用 intro 对话的 700；
# 放在窄容器里（比如事件"公司群"弹窗）时，外面可以调小它，避免气泡超出窗口。
var max_bubble_width: float = MAX_BUBBLE_WIDTH

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

	# 底部 padding 调大，让最后一行离圆角远一点、下方更宽松
	bubble_padding.add_theme_constant_override("margin_bottom", BUBBLE_PAD_BOTTOM)

	var padding_left := bubble_padding.get_theme_constant("margin_left")
	var padding_right := bubble_padding.get_theme_constant("margin_right")
	var padding_top := bubble_padding.get_theme_constant("margin_top")
	var padding_bottom := bubble_padding.get_theme_constant("margin_bottom")

	var target_width := text_width + padding_left + padding_right
	target_width = clamp(target_width, MIN_BUBBLE_WIDTH, max_bubble_width)

	var label_width := target_width - padding_left - padding_right

	# 先用字体粗估一个高度，避免第一帧气泡塌成一条
	var est_h := font.get_multiline_string_size(
		dialogue_text, HORIZONTAL_ALIGNMENT_LEFT, label_width, font_size
	).y
	bubble_patch.custom_minimum_size.x = target_width
	bubble_patch.custom_minimum_size.y = maxf(est_h + padding_top + padding_bottom + BUBBLE_V_EXTRA, MIN_BUBBLE_HEIGHT)

	bubble_label.custom_minimum_size.x = label_width
	bubble_label.custom_minimum_size.y = 0

	# 等布局把文字真正换行后，用 Label 的真实行数×行高把气泡撑到刚好包住文字（再大一圈）。
	# 字体估算常常少算行（WORD_SMART 换行 + 行距），会导致最后一行漏出来，所以要按真实行数二次校正。
	_fit_height_to_content()

# 精确按 Label 换行后的行数把气泡撑高
func _fit_height_to_content() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(bubble_label) or not is_instance_valid(bubble_patch):
		return
	var lines := maxi(bubble_label.get_line_count(), 1)
	var line_h := bubble_label.get_line_height()
	var line_spacing := bubble_label.get_theme_constant("line_spacing")
	var pad_top := bubble_padding.get_theme_constant("margin_top")
	var pad_bottom := bubble_padding.get_theme_constant("margin_bottom")
	# 行数 × 行高 + 行间距，宁可略大也不让文字漏出来
	var content_h := float(lines * line_h + maxi(lines - 1, 0) * line_spacing)
	bubble_patch.custom_minimum_size.y = maxf(content_h + pad_top + pad_bottom + BUBBLE_V_EXTRA, MIN_BUBBLE_HEIGHT)
