extends OptionButton

# 定义选项索引和语言代码的映射
const LOCALE_MAP = {
	0: "zh",
	1: "en"
}

func _ready():
	# 初始化时根据当前的系统语言设置下拉框的选中项
	var current_locale = TranslationServer.get_locale()
	for id in LOCALE_MAP:
		if LOCALE_MAP[id] == current_locale:
			selected = id
			break

func _on_item_selected(index):
	# 1. 获取对应的 Locale 代码
	var locale_code = LOCALE_MAP.get(index, "en")
	
	# 2. 切换引擎的全局语言设置
	TranslationServer.set_locale(locale_code)
	
	# 3. (进阶) 保存配置到本地，防止下次打开重置
	get_tree().reload_current_scene()

func _save_settings(locale):
	var config = ConfigFile.new()
	config.set_value("settings", "locale", locale)
	config.save("user://settings.cfg")
