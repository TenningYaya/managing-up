# pantry_logic.gd
extends OfficeLogic
class_name PantryLogic

func setup(office: Control) -> void:
	super.setup(office)
	# 营业：全局茶水间容量 +1
	OfficeManager.total_pantries += 1
	print("茶水间营业！当前总数：", OfficeManager.total_pantries)

func _on_cleanup() -> void:
	# 关门：全局茶水间容量 -1
	OfficeManager.total_pantries -= 1
	print("茶水间关闭！当前总数：", OfficeManager.total_pantries)
