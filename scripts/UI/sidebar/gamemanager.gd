extends Node

# 1. 定义信号，用来告诉 UI 刷新数字
signal kpi_changed(new_value)
signal dollar_changed(new_value)

# 2. 定义变量
# 当这些变量被修改时，它们会自动广播信号
var kpi: int = 0:
	set(value):
		kpi = value
		kpi_changed.emit(kpi) # 发出广播：KPI 变了！

var dollar: int = 0:
	set(value):
		dollar = value
		dollar_changed.emit(dollar) # 发出广播：Dollar 变了！
