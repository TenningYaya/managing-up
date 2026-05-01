extends Control

# --- 节点引用 ---
# 顶部提示文字 (例如: SPEND 10,000 KPI TO UPGRADE...)
@onready var cost_label = $MainLayout/ScrollContainer/MarginContainer/ItemsList/Label

# Item 1: 工位与等级上限提升
@onready var item1_title = $MainLayout/ScrollContainer/MarginContainer/ItemsList/Item1/VBoxContainer/TitleLabel
@onready var item1_desc = $MainLayout/ScrollContainer/MarginContainer/ItemsList/Item1/VBoxContainer/DescLabel

# Item 2: 办公室数量提升
@onready var item2_title = $MainLayout/ScrollContainer/MarginContainer/ItemsList/Item2/VBoxContainer/TitleLabel
@onready var item2_desc = $MainLayout/ScrollContainer/MarginContainer/ItemsList/Item2/VBoxContainer/DescLabel

# Item 3: 办公室功能解锁
@onready var item3_title = $MainLayout/ScrollContainer/MarginContainer/ItemsList/Item3/VBoxContainer/TitleLabel
@onready var item3_desc = $MainLayout/ScrollContainer/MarginContainer/ItemsList/Item3/VBoxContainer/DescLabel

# 底部升级按钮
@onready var upgrade_button = $UpgradeButton
@onready var upgrade_btn_label = $UpgradeButton/Label

# --- 玩家数据 ---
# 假设当前玩家等级：1代表M1，以此类推。实际项目中建议由 GameManager 统一管理。
var current_level: int = 1 



# --- Upgrade Configuration Data ---
const UPGRADE_DATA = {
	1: { # M1 to M2
		"cost": 100,
		"next_level": "M2",
		"benefits": [
			{"title": "+ DESK SLOT × 1", "desc": "Expand desk slots to 2 rows. Max level increased to 2."},
			{"title": "+ OFFICE × 1", "desc": "Unlock and gain your first independent office."},
			{"title": "+ UNLOCK PANTRY", "desc": "New office function: Pantry, available for staff."}
		]
	},
	2: { # M2 to M3
		"cost": 1000,
		"next_level": "M3",
		"benefits": [
			{"title": "+ DESK SLOT × 1", "desc": "Expand desk slots to 3 rows. Max level increased to 3."},
			{"title": "+ OFFICE × 1", "desc": "Expand the number of offices to 2."},
			{"title": "+ UNLOCK HEADHUNT", "desc": "New office function: Headhunt, to recruit advanced talents."}
		]
	},
	3: { # M3 to M4
		"cost": 5000,
		"next_level": "M4",
		"benefits": [
			{"title": "+ DESK SLOT × 1", "desc": "Expand desk slots to 4 rows. Max level increased to 4."},
			{"title": "+ OFFICE × 1", "desc": "Expand the number of offices to 3."},
			{"title": "+ UNLOCK MEETING", "desc": "New office function: Meeting, for team collaboration."}
		]
	},
	4: { # M4 to M5
		"cost": 10000,
		"next_level": "M5",
		"benefits": [
			{"title": "+ DESK SLOT × 1", "desc": "Expand desk slots to 5 rows. Max level remains at 4."},
			{"title": "+ OFFICE × 1", "desc": "Expand the number of offices to 4."},
			{"title": "+ UNLOCK CULTURE", "desc": "New office function: Culture, to boost company morale."}
		]
	}
}

func _ready():
	# 绑定按钮点击事件
	upgrade_button.pressed.connect(_on_upgrade_button_pressed)
	
	# 界面初始化刷新
	update_ui()

# 刷新界面显示
# 刷新界面显示 (Updated for English)
func update_ui():
	if current_level >= 5:
		# Reached max level M5
		cost_label.text = "REACHED MAX COMPANY LEVEL (M5)"
		upgrade_button.disabled = true
		upgrade_btn_label.text = "MAX LEVEL"
		
		item1_title.text = "-"; item1_desc.text = "MAXED OUT"
		item2_title.text = "-"; item2_desc.text = "MAXED OUT"
		item3_title.text = "-"; item3_desc.text = "MAXED OUT"
		return

	# Get current upgrade data
	var data = UPGRADE_DATA[current_level]
	var cost = data["cost"]
	var next_lv = data["next_level"]

	# Simple comma formatting for thousands (e.g., 1000 -> 1,000)
	var cost_str = str(cost)
	if cost >= 1000:
		cost_str = cost_str.insert(cost_str.length() - 3, ",")

	# 1. Update top text matching your exact layout
	cost_label.text = "SPEND %s KPI TO\nUPGRADE FROM M%d->%s." % [cost_str, current_level, next_lv]
	upgrade_btn_label.text = "M%d -> %s" % [current_level, next_lv]

	# 2. Update the three benefit items
	item1_title.text = data["benefits"][0]["title"]
	item1_desc.text  = data["benefits"][0]["desc"]
	
	item2_title.text = data["benefits"][1]["title"]
	item2_desc.text  = data["benefits"][1]["desc"]
	
	item3_title.text = data["benefits"][2]["title"]
	item3_desc.text  = data["benefits"][2]["desc"]

	# 3. Check KPI balance for button state
	if Gamemanager.has_enough_kpi(cost):
		upgrade_button.disabled = false
	else:
		upgrade_button.disabled = true

# 按钮点击事件处理
func _on_upgrade_button_pressed():
	if current_level >= 5: 
		return
		
	var cost = UPGRADE_DATA[current_level]["cost"]

	# 尝试从全局 Gamemanager 扣除 KPI
	if Gamemanager.spend_kpi(cost):
		print("升级成功！扣除 KPI: ", cost)
		
		# 1. 提升面板自己的显示等级
		current_level += 1
		
		# 🌟 关键修复：同步给全局 Gamemanager！！！
		# 注意：这里要确保 Gamemanager 里的变量名是 player_level
		Gamemanager.player_level = current_level 
		
		# 🌟 关键修复：手动让 Gamemanager 发射信号（如果你在 Gamemanager 里没写 setter 的话）
		if Gamemanager.has_signal("level_changed"):
			Gamemanager.level_changed.emit(Gamemanager.player_level)
		
		# 3. 重新刷新面板UI
		update_ui()
	else:
		print("升级失败，KPI不足！")
