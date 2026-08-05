#employee_information_bar.gd
extends HBoxContainer

@onready var info_icon = $InfoIcon
@onready var info_label = $InfoLabel

# 名字自适应缩放：仅名字栏(NameLabel)开启，稀有度/在职时间栏保持原样不受影响。
# 开启后，若名字宽度超过本行为它预留的空间，就自动调小字号塞进去，绝不把框撑出去。
@export var auto_shrink_name: bool = false
const BASE_FONT_SIZE := 20   # InfoLabel 在场景里的原始字号
const MIN_FONT_SIZE := 10    # 缩到这个下限就不再缩，防止小到看不清

# 🌟 暴露一个变量，让你在编辑器右侧直接选图
@export var icon_texture: Texture2D:
	set(val):
		icon_texture = val
		if is_node_ready():
			$InfoIcon.texture = val

func _ready():
	if icon_texture:
		$InfoIcon.texture = icon_texture
	# 本行宽度在首帧布局完成后才有效；布局变化(尺寸/成员增减)时都重算一遍字号
	if auto_shrink_name:
		resized.connect(_fit_name_font)

func set_value_text(text: String) -> void:
	info_label.text = text
	if auto_shrink_name:
		# 此刻容器可能还没定尺寸，先按当前已知宽度算一次，布局稳定后 resized 会再兜一次
		_fit_name_font()

# 按“本行真实可用宽度”自动选字号：可用宽度 = 整行宽 − 图标 − 铅笔按钮 − 各分隔间距。
# 用运行时实际尺寸计算，面板宽度怎么调都自适应，不写死像素。
func _fit_name_font() -> void:
	if not auto_shrink_name or info_label == null:
		return
	var text: String = info_label.text
	if text == "":
		return

	var font: Font = info_label.get_theme_font("font")
	if font == null:
		return

	# 整行分配宽度是被父容器固定的，与名字长短无关 → 用它减去其它成员，得到留给名字的净空间
	var used := 0.0
	var visible_count := 0
	for c in get_children():
		if c is Control and (c as Control).visible:
			visible_count += 1
			if c != info_label:
				used += (c as Control).size.x
	var sep := float(get_theme_constant("separation"))
	var avail := size.x - used - sep * float(maxi(visible_count - 1, 0))
	if avail <= 0.0:
		return   # 还没布局好，等 resized 再来

	# 量出名字在原始字号下的宽度；超了就按比例缩，没超就恢复原始字号
	var full_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BASE_FONT_SIZE).x
	var target := BASE_FONT_SIZE
	if full_w > avail and full_w > 0.0:
		target = int(floor(BASE_FONT_SIZE * avail / full_w))
	info_label.add_theme_font_size_override("font_size", clampi(target, MIN_FONT_SIZE, BASE_FONT_SIZE))
