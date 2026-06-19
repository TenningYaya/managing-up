#language_selector.gd
extends Control

const SETTINGS_PATH := "user://settings.cfg"

func _ready() -> void:
	# 已经选过语言（settings.cfg 里存了 locale）→ 这个界面一辈子只在第一次出现。
	# settings.cfg 与游戏存档(savegame.json)分离，delete_save() 不会动它，
	# 所以删档重开也会继续用之前的语言、且不再弹选语言界面。
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
