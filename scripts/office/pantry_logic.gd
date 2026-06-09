# pantry_logic.gd
extends OfficeLogic
class_name PantryLogic

func setup(office: Control) -> void:
	super.setup(office)
	# 营业：全局茶水间容量 +1
	OfficeManager.total_pantries += 1
	print("茶水间营业！当前总数：", OfficeManager.total_pantries)

#func _on_cleanup() -> void:
	## 关门：全局茶水间容量 -1
	#OfficeManager.total_pantries -= 1
	#print("茶水间关闭！当前总数：", OfficeManager.total_pantries)

func cleanup() -> void:
	# 关门：全局茶水间容量 -1
	OfficeManager.total_pantries -= 1
	print("茶水间被拆除！当前总数：", OfficeManager.total_pantries)
	
	# 这里什么都不用写了！不抢员工零食，让他们自然吃完。
	
	# 🌟 防漏水补丁：如果你的父类 OfficeLogic 里有 cleanup，记得调用它。
	# 如果没有，就自己把自己销毁，把坑腾出来。
	if super.has_method("cleanup"):
		super.cleanup()
	else:
		queue_free()
