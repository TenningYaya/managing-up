# office_logic.gd
extends Node
class_name OfficeLogic


# 保存对办公室本体的引用，方便获取它的位置或状态
var my_office: Control

# 当芯片被插入办公室时调用
func setup(office: Control) -> void:
	my_office = office

func cleanup() -> void:
	queue_free()
