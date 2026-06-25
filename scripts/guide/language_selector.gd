#language_selector.gd
extends Control

const SETTINGS_PATH := "user://settings.cfg"
const SAVE_PATH := "user://savegame.json"

func _ready() -> void:
	# 选语言界面的出现条件 = 「有没有游戏存档(savegame.json)」：
	#   有存档 → 跳过选语言，沿用 settings.cfg 里上次保存的语言，直接进游戏
	#   无存档 → 弹出选语言界面（每次全新开局都先选语言；删档/挪走存档后重开也会再次出现）
	if FileAccess.file_exists(SAVE_PATH):
		var saved := _load_saved_locale()
		if saved != "":
			TranslationServer.set_locale(saved)
		hide()  # 跳过选语言界面，避免闪一帧
		call_deferred("_start_game")

func _on_btn_chinese_pressed() -> void:
	_choose_language("zh")

func _on_btn_english_pressed() -> void:
	_choose_language("en")

func _choose_language(locale_code: String) -> void:
	TranslationServer.set_locale(locale_code)
	_save_locale(locale_code)   # ← 关键：选完必须存，否则进 main 后会被设置页读默认值覆盖
	_start_game()

func _load_saved_locale() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK and cfg.has_section_key("settings", "locale"):
		return str(cfg.get_value("settings", "locale"))
	return ""

func _save_locale(locale_code: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # 先读，保留 window/always_on_top 等其它设置
	cfg.set_value("settings", "locale", locale_code)
	cfg.save(SETTINGS_PATH)

func _start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
