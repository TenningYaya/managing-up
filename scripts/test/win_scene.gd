#win_scene.gd
extends Control

# 抓取你拖进来的那个对话器组件
@onready var dialogue_ui = $DialogueIntroUI

# ==========================================
# 🌟 核心修改 1：用 @export 暴露台词列表
# 这样你就能在右侧 Inspector 里直接点 "Add Element" 无限加台词了！
# 你在里面直接填你在 CSV 里配好的 ID，比如: WIN_DIALOGUE_01
# ==========================================
@export var win_dialogue_keys: Array[String] = []

func _ready() -> void:
	dialogue_ui.hide()
	dialogue_ui.intro_dialogue_finished.connect(_on_win_dialogue_completed)
	
	# 给画面一秒的留白时间，再开启通关对话
	get_tree().create_timer(1.0).timeout.connect(start_win_sequence)

func start_win_sequence() -> void:
	if win_dialogue_keys.is_empty():
		push_warning("老板，你是不是忘了在 Inspector 里配通关台词了？")
		_on_win_dialogue_completed()
		return
		
	# ==========================================
	# 🌟 核心修改 2：对接本地化系统 (Localization)
	# 因为对话器内部直接使用了数组，为了百分百安全，我们在这里
	# 把 Inspector 里的 Key 先用 tr() 翻译成当前语言的文本，再打包塞给对话器！
	# ==========================================
	var localized_lines: Array[String] = []
	
	for key in win_dialogue_keys:
		# tr() 会自动去你的 CSV 里对暗号，对上了就变成中/英文，对不上就直接显示原字符串
		var translated_text = tr(key) 
		localized_lines.append(translated_text)
	
	# 把已经翻译好的“纯文本数组”灌入对话器，让它逐句播放
	dialogue_ui.start_dialogue(localized_lines, 0, 0.0, 0.0, 0)

# ==========================================
# 4. 对话全部点完（或跳过）后的终极结算
# ==========================================
func _on_win_dialogue_completed() -> void:
	hide()
	queue_free()
