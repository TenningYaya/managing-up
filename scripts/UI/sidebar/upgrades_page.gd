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
	1: { "cost": 50, "next_level": "M2", "benefits": [
		{"title": "Sidebar_UPGRADE_LV1_ITEM1_TITLE", "desc": "Sidebar_UPGRADE_LV1_ITEM1_DESC"},
		{"title": "Sidebar_UPGRADE_LV1_ITEM2_TITLE", "desc": "Sidebar_UPGRADE_LV1_ITEM2_DESC"},
		{"title": "Sidebar_UPGRADE_LV1_ITEM3_TITLE", "desc": "Sidebar_UPGRADE_LV1_ITEM3_DESC"}
	]},
	2: { "cost": 5000, "next_level": "M3", "benefits": [
		{"title": "Sidebar_UPGRADE_LV2_ITEM1_TITLE", "desc": "Sidebar_UPGRADE_LV2_ITEM1_DESC"},
		{"title": "Sidebar_UPGRADE_LV2_ITEM2_TITLE", "desc": "Sidebar_UPGRADE_LV2_ITEM2_DESC"},
		{"title": "Sidebar_UPGRADE_LV2_ITEM3_TITLE", "desc": "Sidebar_UPGRADE_LV2_ITEM3_DESC"}
	]},
	3: { "cost": 30000, "next_level": "M4", "benefits": [
		{"title": "Sidebar_UPGRADE_LV3_ITEM1_TITLE", "desc": "Sidebar_UPGRADE_LV3_ITEM1_DESC"},
		{"title": "Sidebar_UPGRADE_LV3_ITEM2_TITLE", "desc": "Sidebar_UPGRADE_LV3_ITEM2_DESC"},
		{"title": "Sidebar_UPGRADE_LV3_ITEM3_TITLE", "desc": "Sidebar_UPGRADE_LV3_ITEM3_DESC"}
	]},
	4: { "cost": 100000, "next_level": "M5", "benefits": [
		{"title": "Sidebar_UPGRADE_LV4_ITEM1_TITLE", "desc": "Sidebar_UPGRADE_LV4_ITEM1_DESC"},
		{"title": "Sidebar_UPGRADE_LV4_ITEM2_TITLE", "desc": "Sidebar_UPGRADE_LV4_ITEM2_DESC"},
		{"title": "Sidebar_UPGRADE_LV4_ITEM3_TITLE", "desc": "Sidebar_UPGRADE_LV4_ITEM3_DESC"}
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
		cost_label.text = tr("Sidebar_UPGRADE_MAX_TITLE")
		upgrade_button.disabled = true
		upgrade_btn_label.text = tr("Sidebar_UPGRADE_BTN_MAXED")

		item1_title.text = "-"; item1_desc.text = tr("Sidebar_UPGRADE_MAXED_OUT")
		item2_title.text = "-"; item2_desc.text = tr("Sidebar_UPGRADE_MAXED_OUT")
		item3_title.text = "-"; item3_desc.text = tr("Sidebar_UPGRADE_MAXED_OUT")
		return

	var data = UPGRADE_DATA[current_level]
	var cost = data["cost"]
	var next_lv = data["next_level"]

	var cost_str = str(cost)
	if cost >= 1000:
		cost_str = cost_str.insert(cost_str.length() - 3, ",")

	cost_label.text = _fmt("Sidebar_UPGRADE_COST_FORMAT", [cost_str, current_level, next_lv])
	upgrade_btn_label.text = _fmt("Sidebar_UPGRADE_BTN_FORMAT", [current_level, next_lv])

	item1_title.text = tr(data["benefits"][0]["title"])
	item1_desc.text  = tr(data["benefits"][0]["desc"])
	item2_title.text = tr(data["benefits"][1]["title"])
	item2_desc.text  = tr(data["benefits"][1]["desc"])
	item3_title.text = tr(data["benefits"][2]["title"])
	item3_desc.text  = tr(data["benefits"][2]["desc"])

	# 检查余额 [cite: 8, 9]
	upgrade_button.disabled = not Gamemanager.has_enough_kpi(cost)

# 安全格式化：
# 1) 翻译缺失时 tr() 会原样返回 key（不含 %s/%d）；
# 2) 翻译数据过期 / 占位符数量与参数不一致时，
# 直接 % 会报 “not all arguments converted” 并崩溃。
# 因此仅当占位符数量与参数数量一致时才做 % 格式化，否则原样返回，避免崩溃。
func _fmt(key: String, args: Array) -> String:
	var s := tr(key)
	if s == key:
		return s
	if _count_format_specifiers(s) != args.size():
		push_warning("翻译 '%s' 的占位符数量与参数(%d 个)不匹配，请重新导入翻译。" % [key, args.size()])
		return s
	return s % args

# 统计 printf 风格占位符数量（%s/%d 等）；%% 为转义，不计入。
func _count_format_specifiers(s: String) -> int:
	var count := 0
	var i := 0
	while i < s.length():
		if s[i] == "%":
			if i + 1 < s.length() and s[i + 1] == "%":
				i += 2 # 转义的 %%
				continue
			count += 1
		i += 1
	return count

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
