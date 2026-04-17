# meeting_room_logic.gd
extends OfficeLogic
class_name MeetingRoomLogic

func setup(office: Control) -> void:
	super.setup(office)
	# 可以在这里把茶水间加入全局管理，比如：Globals.pantry_count += 1
	print("茶水间开始营业，准备发零食Buff！")

func cleanup() -> void:
	# Globals.pantry_count -= 1
	print("茶水间关闭，停止发Buff。")
	queue_free() # 销毁这个节点
