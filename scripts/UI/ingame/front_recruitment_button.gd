#front_recruitment_button
extends Button

func _on_pressed() -> void:
	var panel = get_tree().get_first_node_in_group("recruitment_panel")
	if panel:
		# 教程锁定期间：只许开、不许关。否则玩家再点一下按钮就把教程要求打开的面板 toggle 掉了
		if panel.get("is_locked_by_tutorial") == true:
			panel.show()
			return
		if panel.visible:
			panel.visible = !panel.visible
			return
		else:
			panel.show()
