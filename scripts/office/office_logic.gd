# office_logic.gd
extends Node
class_name OfficeLogic

# 保存对办公室本体的引用，方便获取它的位置或状态
var my_office: Control

# 当芯片被插入办公室时调用
func setup(office: Control) -> void:
	my_office = office
	print("功能已装载")

# 当办公室被换成其他功能时调用（用于清理计时器、归还员工等）
func cleanup() -> void:
	print("功能已卸载")
