#language_selector.gd
extends Control

func _on_btn_chinese_pressed():
	TranslationServer.set_locale("zh")  # 强行切换为中文
	_start_game()

func _on_btn_english_pressed():
	TranslationServer.set_locale("en")  # 强行切换为英文
	_start_game()

func _start_game():
	# 切换完毕后，加载你的教程第一关
	get_tree().change_scene_to_file("res://scenes/main.tscn")
