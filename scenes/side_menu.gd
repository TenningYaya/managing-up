extends Control

var open_x = 1570  # 展开时的坐标
var close_x = 1840 # 收起时的坐标
var is_open = false # 记录菜单现在是开还是关

# 这个函数专门负责“伸缩”动画
func toggle_menu():
	# 切换状态
	is_open = !is_open
	
	# 修复后的逻辑：如果是 open 状态，就去 open_x；否则去 close_x
	var target_x = open_x if is_open else close_x
	
	# 执行动画
	var tween = create_tween()
	tween.tween_property(self, "position:x", target_x, 0.3).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	
# 2. 在各个信号里“调用”它
func _on_general_pressed():
	toggle_menu()

func _on_hire_pressed():
	toggle_menu()

func _on_upgrades_pressed():
	toggle_menu()

func _on_settings_pressed():
	toggle_menu()
