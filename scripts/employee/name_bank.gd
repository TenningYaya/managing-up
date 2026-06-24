# name_bank.gd (静态工具)
class_name NameBank

# 英文名与中文名按行对齐：first_names[i] 与 first_names_zh[i] 是同一个人的两种语言写法
static var first_names: PackedStringArray = []
static var first_names_zh: PackedStringArray = []

static func load_names() -> void:
	if first_names.size() > 0: return # 避免重复加载
	first_names = FileAccess.get_file_as_string("res://data/employee/first_names.txt").split("\n", false)
	first_names_zh = FileAccess.get_file_as_string("res://data/employee/first_names_zh.txt").split("\n", false)

# 随机返回一个名字“下标”，存进 employee.name_index。
# 之后显示名按当前语言用 get_name(index) 实时解析，所以同一个员工切语言会自动变名字。
static func get_random_index() -> int:
	load_names()
	if first_names.is_empty():
		return -1
	return randi() % first_names.size()

# 把下标解析成当前语言的名字。中文 locale 且中文表长度对得上才用中文，否则回退英文。
# ⚠️ 不能叫 get_name：那会和基类内置的 0 参数 get_name 冲突。
static func get_localized_name(index: int) -> String:
	load_names()
	var use_zh := TranslationServer.get_locale().begins_with("zh") and first_names_zh.size() == first_names.size()
	var arr := first_names_zh if use_zh else first_names
	if index < 0 or index >= arr.size():
		return "Angela Baby" # 保底名字
	return arr[index]

# 按英文名反查下标（给场景里预置/老存档里只有英文名、没有 name_index 的员工用）
static func index_of(en_name: String) -> int:
	load_names()
	for i in first_names.size():
		if first_names[i] == en_name:
			return i
	return -1

# 兼容旧调用：直接返回当前语言的一个随机名字
static func get_random_name() -> String:
	return get_localized_name(get_random_index())
