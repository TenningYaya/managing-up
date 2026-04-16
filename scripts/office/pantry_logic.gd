# pantry_logic.gd
extends OfficeLogic
class_name PantryLogic

# 这里的 Node2D 必须改为 Control，以匹配父类 OfficeLogic 的定义
func setup(office: Control) -> void:
	super.setup(office)
	# 以后可以在这里把茶水间加入全局管理
	print("茶水间开始营业，准备发零食Buff！")

func _on_cleanup() -> void:
	print("茶水间关闭，停止发Buff。")
	# 注意：如果你在 OfficeLogic 的 cleanup() 里写了 queue_free()，
	# 那么子类就不需要再写一遍了。
