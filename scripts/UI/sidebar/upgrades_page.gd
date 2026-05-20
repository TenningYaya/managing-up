extends Control

# --- Node References (保持不变) ---
@onready var cost_label = $MainLayout/ScrollContainer/MarginContainer/ItemsList/Label
@onready var item1_title = $MainLayout/ScrollContainer/MarginContainer/ItemsList/Item1/VBoxContainer/TitleLabel
@onready var item1_desc = $MainLayout/ScrollContainer/MarginContainer/ItemsList/Item1/VBoxContainer/DescLabel
@onready var item2_title = $MainLayout/ScrollContainer/MarginContainer/ItemsList/Item2/VBoxContainer/TitleLabel
@onready var item2_desc = $MainLayout/ScrollContainer/MarginContainer/ItemsList/Item2/VBoxContainer/DescLabel
@onready var item3_title = $MainLayout/ScrollContainer/MarginContainer/ItemsList/Item3/VBoxContainer/TitleLabel
@onready var item3_desc = $MainLayout/ScrollContainer/MarginContainer/ItemsList/Item3/VBoxContainer/DescLabel
@onready var upgrade_button = $UpgradeButton
@onready var upgrade_btn_label = $UpgradeButton/Label
@onready var clicked_sound: AudioStreamPlayer = $ClickedSound

# --- Upgrade Configuration Data (保持不变) ---
const UPGRADE_DATA = {
	1: { "cost": 100, "next_level": "M2", "benefits": [
		{"title": "+ DESK SLOT × 1 ROW", "desc": "Expand desk slots to 2 rows. Max level increased to 2."},
		{"title": "+ OFFICE × 1", "desc": "Unlock and gain your first independent office."},
		{"title": "+ UNLOCK PANTRY", "desc": "New office function: Pantry, available for staff."}
	]},
	2: { "cost": 1000, "next_level": "M3", "benefits": [
		{"title": "+ DESK SLOT × 1 ROW", "desc": "Expand desk slots to 3 rows. Max level increased to 3."},
		{"title": "+ OFFICE × 1", "desc": "Expand the number of offices to 2."},
		{"title": "+ UNLOCK HEADHUNT", "desc": "New office function: Headhunt, to recruit advanced talents."}
	]},
	3: { "cost": 5000, "next_level": "M4", "benefits": [
		{"title": "+ DESK SLOT × 1 ROW", "desc": "Expand desk slots to 4 rows. Max level increased to 4."},
		{"title": "+ OFFICE × 1", "desc": "Expand the number of offices to 3."},
		{"title": "+ UNLOCK MEETING", "desc": "New office function: Meeting, for team collaboration."}
	]},
	4: { "cost": 10000, "next_level": "M5", "benefits": [
		{"title": "+ DESK SLOT × 1 ROW", "desc": "Expand desk slots to 5 rows. Max level remains at 4."},
		{"title": "+ OFFICE × 1", "desc": "Expand the number of offices to 4."},
		{"title": "+ UNLOCK CULTURE", "desc": "New office function: Culture, to boost company morale."}
	]}
}

func _ready():
	upgrade_button.pressed.connect(_on_upgrade_button_pressed)
	# 也可以监听 GameManager 里的 kpi_changed 来实时刷新按钮状态
	Gamemanager.kpi_changed.connect(func(_new_kpi): update_ui())
	update_ui()

func update_ui():
	var current_level = Gamemanager.player_level # 直接从 Gamemanager 获取

	if current_level >= 5:
		cost_label.text = "REACHED MAX COMPANY LEVEL (M5)"
		upgrade_button.disabled = true
		upgrade_btn_label.text = "MAX LEVEL"
		
		item1_title.text = "-"; item1_desc.text = "MAXED OUT"
		item2_title.text = "-"; item2_desc.text = "MAXED OUT"
		item3_title.text = "-"; item3_desc.text = "MAXED OUT"
		return

	var data = UPGRADE_DATA[current_level]
	var cost = data["cost"]
	var next_lv = data["next_level"]

	var cost_str = str(cost)
	if cost >= 1000:
		cost_str = cost_str.insert(cost_str.length() - 3, ",")

	cost_label.text = "SPEND %s KPI TO\nUPGRADE FROM M%d->%s." % [cost_str, current_level, next_lv]
	upgrade_btn_label.text = "M%d -> %s" % [current_level, next_lv]

	item1_title.text = data["benefits"][0]["title"]
	item1_desc.text  = data["benefits"][0]["desc"]
	item2_title.text = data["benefits"][1]["title"]
	item2_desc.text  = data["benefits"][1]["desc"]
	item3_title.text = data["benefits"][2]["title"]
	item3_desc.text  = data["benefits"][2]["desc"]

	# 检查余额 [cite: 8, 9]
	upgrade_button.disabled = not Gamemanager.has_enough_kpi(cost)

func _on_upgrade_button_pressed():
	if Gamemanager.player_level >= 5: 
		return
		
	var cost = UPGRADE_DATA[Gamemanager.player_level]["cost"]

	if Gamemanager.spend_kpi(cost):
		# 更新等级，这里会自动触发你 Gamemanager 里的 level_changed 信号！ 
		Gamemanager.player_level += 1
		
		# 同步更新你的工位状态 
		Gamemanager.unlocked_desk_slots = Gamemanager.player_level
		Gamemanager.max_desk_level = min(Gamemanager.player_level, 4) 
		
		update_ui()
		clicked_sound.play()
