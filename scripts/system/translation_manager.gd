# translation_manager.gd
extends Node

# 广播信号：告诉全场 UI 语言换了，赶紧刷新！
signal language_changed

# 支持的语言列表
const LANG_ZH = "zh"
const LANG_EN = "en"

var current_locale: String = LANG_ZH

func _ready() -> void:
	# 游戏启动时，初始化语言（也可以在这里读取玩家的存档配置）
	set_language(LANG_EN)

## 🌟 核心函数：一键切换全场语言
func set_language(locale_code: String) -> void:
	current_locale = locale_code
	
	# 1. 改变 Godot 引擎底层的翻译语系
	TranslationServer.set_locale(locale_code)
	
	# 2. 轰炸式广播：让所有连了这个信号的 UI 组件集体原地变形！
	language_changed.emit()
