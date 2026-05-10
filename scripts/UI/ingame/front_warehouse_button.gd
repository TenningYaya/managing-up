extends Button

func _on_pressed() -> void:
	var panel = get_tree().get_first_node_in_group("employee_warehouse")
	if panel:
		if panel.visible:
			panel.visible = !panel.visible
			return
		else:
			panel.refresh_display()
			panel.show()
	
