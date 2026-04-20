extends Control
class_name DeskSlot

var slot_level: int = 1

@onready var grid_container = $CenterContainer/GridContainer
@onready var click_area = $ClickArea # 你刚才加的那个透明按钮

func _ready():
	click_area.pressed.connect(_on_slot_clicked)

func _on_slot_clicked():
	# 从场景树里找到刚刚写好的那个升级面板
	var panel = get_tree().get_first_node_in_group("upgrade_panel")
	if panel:
		panel.open(self)

# 统一升级这 6 个座位
func upgrade_all():
	if slot_level < 4:
		slot_level += 1
		# 遍历 GridContainer 里的 6 个 DeskSet
		for desk in grid_container.get_children():
			# 确保它有你 seat.gd 里的那个方法
			if desk is DeskSeat: 
				desk.set_upgrade_level(slot_level)
