#stack_row.gd
extends Button
class_name StockRow

signal selected(index: int)

@onready var name_label: Label = $Columns/Name
@onready var price_label: Label = $Columns/Price
@onready var held_label: Label = $Columns/Held
@onready var pl_label: Label = $Columns/PL
@onready var highlight: ColorRect = $Highlight

# 刻板印象:红涨绿跌
const COL_UP := Color(0.88, 0.27, 0.27)    # 涨 = 红
const COL_DOWN := Color(0.22, 0.70, 0.38)  # 跌 = 绿
const COL_FLAT := Color(0.82, 0.82, 0.82)  # 平 = 中性

var index: int = -1

func _ready() -> void:
	pressed.connect(func(): selected.emit(index))

func setup(i: int) -> void:
	index = i
	refresh()

func refresh() -> void:
	name_label.text = StockManager.get_display_name(index)
	price_label.text = str(StockManager.get_price(index))
	var held := StockManager.get_holdings(index)
	held_label.text = str(held)
	pl_label.text = _pl_text(held)

	# 整行染色:涨→红、跌→绿、平→中性
	var trend := StockManager.get_trend(index)   # +1 涨 / -1 跌 / 0 平
	var c := COL_FLAT
	if trend > 0:
		c = COL_UP
	elif trend < 0:
		c = COL_DOWN
	for l in [name_label, price_label, held_label, pl_label]:
		l.add_theme_color_override("font_color", c)

func _pl_text(held: int) -> String:
	if held <= 0:
		return "—"
	var p := StockManager.get_profit(index)
	return ("+" + str(p)) if p > 0 else str(p)

func set_selected(on: bool) -> void:
	highlight.visible = on
