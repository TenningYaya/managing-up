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
		
	# 如果你用了 NinePatchRect 做底图，或者用了 Container 自动排版
	# 强行让它在这一帧重新计算一下物理宽高，防止字溢出
	await get_tree().process_frame
