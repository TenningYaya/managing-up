# speedup_quote_save.gd (Autoload)
extends Node

const SAVE_PATH = "user://boss_quotes.json"

# 默认台词
var boss_quotes: Array = [
	"BOSS_QUOTE_01",
	"BOSS_QUOTE_02", 
    "BOSS_QUOTE_03"
]

#默认的存一下
#var boss_quotes: Array = [
	#"总感觉怪怪的你再改改",
	#"快打包了什么时候做完啊",
	#"老师这就是成图了吗"
#]

func _ready() -> void:
	load_quotes()

func add_quote(text: String):
	if text != "" and not boss_quotes.has(text):
		boss_quotes.append(text)
		save_quotes()

func remove_quote(index: int):
	if boss_quotes.size() > 1: # 至少留一句，不然会报错
		boss_quotes.remove_at(index)
		save_quotes()

func get_random_quote() -> String:
	return tr(boss_quotes[randi() % boss_quotes.size()])

# --- 持久化存储 ---
func save_quotes():
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(boss_quotes))

func load_quotes():
	if FileAccess.file_exists(SAVE_PATH):
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		var json_data = JSON.parse_string(file.get_as_text())
		if json_data is Array:
			boss_quotes = json_data
