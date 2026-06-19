extends OptionButton

# 定义选项索引和语言代码的映射
const LOCALE_MAP = {
	0: "zh",
	1: "en"
}

func _ready():
	item_selected.connect(_on_item_selected)
	_load_settings()
	var current_locale = TranslationServer.get_locale()
	for id in LOCALE_MAP:
		if current_locale.begins_with(LOCALE_MAP[id]):
			selected = id
			break

func _on_item_selected(index: int) -> void:
	var locale_code: String = LOCALE_MAP.get(index, "en")
	TranslationServer.set_locale(locale_code)
	_save_settings(locale_code)

func _save_settings(locale: String) -> void:
	var config := ConfigFile.new()
	config.load("user://settings.cfg")  # 先读，避免覆盖掉 window/always_on_top 等其它设置
	config.set_value("settings", "locale", locale)
	config.save("user://settings.cfg")

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		# 默认值用“当前 locale”而不是写死 "zh"，避免在没有 locale 记录时把语言强制掰回中文
		var locale: String = config.get_value("settings", "locale", TranslationServer.get_locale())
		TranslationServer.set_locale(locale)
