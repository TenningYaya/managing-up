extends OfficeLogic
class_name BulletinBoardLogic

func setup(office: Control) -> void:
	super.setup(office)
	# 登记为已存在，会自动发出信号
	OfficeManager.has_bulletin_board = true

func cleanup() -> void:
	# 撤销登记
	OfficeManager.has_bulletin_board = false
	super.cleanup()
