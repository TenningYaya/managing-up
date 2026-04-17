extends Control

# 当这个 UI 准备好时
func _ready():
	# 1. 游戏刚开始，先去管家那里问一下现在的钱数，进行第一次 更新 (Update)
	update_labels()
	
	# 2. 连接 (Connect) 管家的广播信号
	# 只要 GameManager 广播说钱变了，就执行我们下面写好的刷新函数
	Gamemanager.kpi_changed.connect(_on_kpi_updated)
	Gamemanager.dollar_changed.connect(_on_dollar_updated)


# 这个函数专门负责刷新 KPI 的文字
func _on_kpi_updated(new_value):
	$ColorRect/MarginContainer/VBoxContainer/KPI/KPILabel.text = str(new_value)

# 这个函数专门负责刷新 Dollar 的文字
func _on_dollar_updated(new_value):
	$ColorRect/MarginContainer/VBoxContainer/KPI2/DollarLabel.text = str(new_value)

# 初始 更新 函数
func update_labels():
	$ColorRect/MarginContainer/VBoxContainer/KPI/KPILabel.text = str(Gamemanager.kpi)
	$ColorRect/MarginContainer/VBoxContainer/KPI2/DollarLabel.text = str(Gamemanager.dollar)
