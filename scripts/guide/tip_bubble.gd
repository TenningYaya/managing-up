# tip_bubble.gd
extends Control
class_name TutorialTip

@onready var label: Label = $Label

func _ready() -> void:
	# 💥 降维打击：防止 Tips 自己把玩家的鼠标点击给中途打劫了！
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# 最高通行证：确保自己踩在全场最头顶
	z_index = 1000
	z_as_relative = false

## 🌟 核心对外接口：设置文本，并根据文本长短自动撑开底图
func set_tip(text_content: String) -> void:
	if label:
		label.text = text_content

	# 等两帧让 Label（尤其中文，文本塑形较慢）算好真实尺寸,再强制底图按内容收缩贴合,
	# 这样中英文都有足够竖向空间,不会被切顶/切底/压扁。
	await get_tree().process_frame
	await get_tree().process_frame
	reset_size()
