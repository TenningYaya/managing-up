# tutorial_step.gd
# 🌟 终极关卡剧本数据模具 - 支持全节点动态吸附与像素级自由微调
extends Resource
class_name TutorialStep

enum Type { 
	DIALOGUE,     # 纯对话 (如果填了 target_group 则会自动触发“只高亮解说不卡点击”的特效)
	FOCUS_CLICK,  # 强行挖洞点击 (黑布挖洞 + Tips 提示 + 强迫点击按钮三位一体)
	WAIT_EVENT    # 纯逻辑等待
}

enum Speaker { 
	BOSS, 
	KPI_BAO 
}
enum TipPos { TOP, BOTTOM, LEFT, RIGHT }
enum DialoguePos { CENTER_PHONE, RIGHT_PHONE, TOP_WINDOW, BOTTOM_WINDOW }

@export_group("Core Logic")
## 这一步引导的交互类型
@export var step_type: Type = Type.DIALOGUE
## 这一步需要监听的目标节点组名（例如 "recruitment_button"），不需要挖洞则留空
@export var target_group: String = ""
## 触发下一步所需的引擎信号（例如 "pressed"、"project_name_confirmed"）
@export var wait_signal: String = "pressed"
@export var disable_reject_buttons: bool = false

@export_group("Auto UI Trigger")
## 这一步需要大总管强制弹出的 UI 组名（例如 "sidebar_panel"、"notebook_panel"），不需要则留空
@export var force_show_ui_group: String = ""
@export var extra_show_group: String = ""
## 是否在这一步锁定该 UI，不允许它被任何玩家操作意外关闭（通常 FOCUS_CLICK 时设为 true）
@export var lock_ui_lifecycle: bool = false
@export var disable_employee_interaction: bool = true
@export var show_blocker: bool = true

@export_group("Dialogue UI")
@export var speaker: Speaker = Speaker.BOSS
## 决定 KPI宝 或老板在屏幕的哪个基础位置探出来
@export var dialogue_position: DialoguePos = DialoguePos.RIGHT_PHONE
## 🌟 新增：对话框弹出来之前的“无声高亮”装逼时间（秒）。设为 0 就直接弹。
@export var delay_before_dialogue: float = 0.0
## 这一步要播放的剧情台词数组（支持单句或多句连播）
@export_multiline var dialogue_lines: Array[String] = []

@export_group("Illustration Feature")
## 这一步需要弹出的提示截图（不需要则留空）
@export var illustration_texture: Texture2D
@export var illustration_en: Texture2D # 英文版（默认）插图
@export var illustration_zh: Texture2D # 中文版插图
## 截图像素微调偏移（正数向右下，负数向左上）
@export var illustration_offset: Vector2 = Vector2.ZERO

@export_subgroup("Dialogue Pixel Fine-Tuning")
## 🌟 对话框像素微调：在基础预设位置上，水平方向偏移的像素值（正数向右，负数向左）
@export var dialogue_offset_x: float = 0.0
## 🌟 对话框像素微调：在基础预设位置上，垂直方向偏移的像素值（正数向下，负数向上）
@export var dialogue_offset_y: float = 0.0

@export_group("Helper Tip UI")
## 漂浮在目标按钮旁边、清晰描述操作的提示小字（例如 "点击这里招募"）
@export var tip_text: String = ""
## 决定提示小字和箭头默认吸附在目标的哪一侧
@export var tip_position: TipPos = TipPos.TOP

@export_subgroup("Tip Pixel Fine-Tuning")
## 🌟 提示小字像素微调：在默认吸附位置的基础上，水平方向偏移的像素值（正数向右，负数向左）
@export var tip_offset_x: float = 0.0
## 🌟 提示小字像素微调：在默认吸附位置的基础上，垂直方向偏移的像素值（正数向下，负数向上）
@export var tip_offset_y: float = 0.0
