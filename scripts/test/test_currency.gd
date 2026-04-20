extends Control

# 注意：这个脚本挂在 TestCurrency 根节点上
# 它会自动搜索并连接子节点按钮的信号

func _ready() -> void:
	# 指向 VBoxContainer 这个节点
	var container = $VBoxContainer 
	
	for btn in container.get_children():
		if btn is Button or btn is BaseButton:
			_bind_button_logic(btn)

func _bind_button_logic(btn: Node):
	# 根据按钮的名字（Name）来绑定对应的逻辑
	# 建议你的按钮名字直接改成 KPI+100, USD+10000 这种
	var b_name = btn.name
	
	match b_name:
		"KPI+100":
			btn.pressed.connect(func(): Gamemanager.add_kpi(100))
		"KPI+1000":
			btn.pressed.connect(func(): Gamemanager.add_kpi(1000))
		"KPI+1000000":
			btn.pressed.connect(func(): Gamemanager.add_kpi(1000000))
		"USD+100":
			btn.pressed.connect(func(): Gamemanager.add_dollar(100))
		"USD+10000":
			btn.pressed.connect(func(): Gamemanager.add_dollar(10000))
		"KPI0":
			btn.pressed.connect(_clear_kpi)
		"USD0":
			btn.pressed.connect(_clear_dollar)

# ================= 归零逻辑 =================
# 假设你的 Gamemanager 里的变量名是 kpi 和 dollar
# 归零通常需要直接操作变量或者调一个特殊的设置方法

func _clear_kpi():
	Gamemanager.kpi = 0
	# 如果你有刷新 UI 的信号，记得手动触发一下或者确保 Gamemanager 内部会处理
	print("KPI 已归零")

func _clear_dollar():
	Gamemanager.dollar = 0
	print("美金已归零")
