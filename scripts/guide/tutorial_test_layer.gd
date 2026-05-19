# 假设这是你 TutorialTestLayer 的总脚本，用来调度它们：
extends CanvasLayer # 或者 Control

@onready var dialogue_ui = $DialogueIntroUI # 你同学写的对话界面节点名
@onready var blocker_ui = $Blocker         # 刚才做的4块黑布节点名

func _ready() -> void:
	# 1. 确保游戏一上来，黑布指引是藏起来的
	blocker_ui.hide()
	
	# 2. 核心接力：监听对话 UI 发出的“我播完了”信号！
	dialogue_ui.intro_dialogue_finished.connect(_on_intro_dialogue_finished)

func _on_intro_dialogue_finished() -> void:
	print("【总控】收到对话结束信号！现在开启招聘按钮指引...")
	
	# 3. 呼叫黑布脚本，让它原地生成 4 块布围攻招聘按钮！
	blocker_ui.start_button_tutorial()
	
	# 4. 这个时候再过河拆桥，把已经没用的对话界面彻底释放掉
	dialogue_ui.queue_free()
