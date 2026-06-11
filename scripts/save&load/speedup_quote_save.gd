# speedup_quote_save.gd (Autoload)
extends Node

# 🌟 不再需要独立的 SAVE_PATH 和 IO 操作了
const DEFAULT_QUOTES: Array = [
	"BOSS_QUOTE_01",
	"BOSS_QUOTE_02", 
	"BOSS_QUOTE_03"
]

var boss_quotes: Array = []

func _ready() -> void:
	# 启动时先塞默认值，稍后如果主存档里有，会被主存档覆盖
	reset_to_default()

func add_quote(text: String):
	if text != "" and not boss_quotes.has(text):
		boss_quotes.append(text)
		# 🌟 通知主存档系统去落盘
		SaveManager.save_game()

func remove_quote(index: int):
	if boss_quotes.size() > 1: # 至少留一句，不然会报错
		boss_quotes.remove_at(index)
		# 🌟 通知主存档系统去落盘
		SaveManager.save_game()

func get_random_quote() -> String:
	return tr(boss_quotes[randi() % boss_quotes.size()])

# 🌟 新增：重置为默认台词（供删档重开使用）
func reset_to_default() -> void:
	boss_quotes = DEFAULT_QUOTES.duplicate()
