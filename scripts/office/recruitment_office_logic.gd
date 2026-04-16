# recruitment_office_logic.gd
extends OfficeLogic
class_name RecruitmentOfficeLogic

func setup(office: Control) -> void:
	super.setup(office)
	# 登记为已存在，会自动发出信号
	OfficeManager.has_recruitment_office = true
	print("招聘办公室已上线！")

func cleanup() -> void:
	# 撤销登记
	OfficeManager.has_recruitment_office = false
	print("招聘办公室已下线。")
	super.cleanup()
