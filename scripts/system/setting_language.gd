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
	config.set_value("settings", "locale", locale)
	config.save("user://settings.cfg")

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		var locale: String = config.get_value("settings", "locale", "zh")
		TranslationServer.set_locale(locale)
