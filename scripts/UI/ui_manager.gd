extends Node

# --- 预载常用的 UI 场景，省去每次都写路径的麻烦 ---
const CULTURE_PANEL_SCENE = preload("res://scenes/UI/panel/culture_panel.tscn")
# const RECRUIT_PANEL_SCENE = preload("res://scenes/ui/RecruitPanel.tscn") # 预留

# 保存对窗口母节点的引用
var window_container: Control = null

func _ready() -> void:
	# 自动寻找场景树里的挂载点
	# 假设你在主场景里放了一个叫 "WindowContainer" 的节点
	window_container = get_tree().root.find_child("WindowContainer", true, false)

# ==========================================
# 核心功能：打开企业文化面板
# ==========================================
func open_culture_panel(logic_ref: CultureCenterLogic) -> void:
	# 1. 检查母节点是否存在
	if not window_container:
		push_error("UIManager: 找不到 WindowContainer！请检查主场景。")
		return
		
	# 2. 防重复打开（可选）：如果已经开着一个了，就别开了，或者关掉旧的
	var old_panel = window_container.get_node_or_null("CulturePanel")
	if old_panel:
		old_panel.queue_free()

	# 3. 实例化并添加
	var panel = CULTURE_PANEL_SCENE.instantiate()
	window_container.add_child(panel)
	
	# 4. 【核心点】：把办公室逻辑传给面板，让面板里的按钮知道该改谁
	if panel.has_method("setup"):
		panel.setup(logic_ref)
	
	print("UIManager: 已打开企业文化面板")

# ==========================================
# 通用功能：关闭所有窗口
# ==========================================
func close_all_windows() -> void:
	for child in window_container.get_children():
		child.queue_free()
