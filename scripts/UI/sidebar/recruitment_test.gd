# recruitment_test.gd
extends Node

# 测试节点只需要简单的导出变量连到按钮上
func _on_test_normal_gen_pressed():
	RecruitmentManager.auto_generate_normal()

func _on_test_headhunt_1x_pressed():
	if Gamemanager.spend_dollar(1):
		RecruitmentManager.start_headhunt(1, 1.0)

func _on_clear_all_test():
	RecruitmentManager.normal_pool.clear()
	RecruitmentManager.headhunt_pool.clear()
