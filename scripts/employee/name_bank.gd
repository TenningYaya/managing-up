# name_bank.gd (静态工具)
class_name NameBank

static var first_names: PackedStringArray = []
static var last_names: PackedStringArray = []

static func load_names():
	if first_names.size() > 0: return # 避免重复加载
	
	# 假设你把名字存在了文本文件里，每行一个
	first_names = FileAccess.get_file_as_string("res://data/first_names.txt").split("\n", false)
	last_names = FileAccess.get_file_as_string("res://data/last_names.txt").split("\n", false)

static func get_random_name() -> String:
	#if first_names.is_empty() or last_names.is_empty():
		#return "Angela Baby" # 保底名字
	#var first = Array(first_names).pick_random()
	#var last = Array(last_names).pick_random()
	#
	#return first + " " + last
	if first_names.is_empty() or last_names.is_empty():
		return "Angela Baby" # 保底名字
	var first = Array(first_names).pick_random()
	
	return first
