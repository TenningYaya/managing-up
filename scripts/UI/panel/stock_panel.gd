# stock_panel.gd —— 炒股交易页
# 结构:
#   Control(本脚本)
#   └─ StockContainer (VBoxContainer)
#       ├─ StockList     (VBoxContainer) ← 实例化 stack_row.tscn(每行=StockRow,样式/字体在那个场景里调)
#       ├─ RichTextLabel                  ← 选中股票的详情读数(持有/成本/现价/盈亏)
#       ├─ BuyRow        (TradeRow)
#       └─ SellRow       (TradeRow)
extends Control

const STOCK_ROW := preload("res://scenes/UI/panel/stack_row.tscn")

@onready var stock_list: VBoxContainer = $StockContainer/StockPanel/StockList
@onready var detail: RichTextLabel = $StockContainer/TradePanel/InfoContainer/InfoList/RichTextLabel
@onready var buy_row: TradeRow = $StockContainer/TradePanel/InfoContainer/InfoList/BuyRow
@onready var sell_row: TradeRow = $StockContainer/TradePanel/InfoContainer/InfoList/SellRow

var _rows: Array = []          # StockRow 实例
var _selected: int = -1

func _ready() -> void:
	detail.bbcode_enabled = true
	detail.fit_content = true
	detail.scroll_active = false

	# 上半:实例化股票行(用你的 stack_row.tscn,字体/样式都归它)
	for i in range(StockManager.get_stock_count()):
		var row: StockRow = STOCK_ROW.instantiate()
		row.size_flags_horizontal = Control.SIZE_FILL   # 撑满 StockList 宽度
		stock_list.add_child(row)
		row.setup(i)
		row.selected.connect(_on_selected)
		_rows.append(row)

	# 下半:买/卖两行定模式
	buy_row.set_mode(TradeRow.Mode.BUY)
	sell_row.set_mode(TradeRow.Mode.SELL)

	# 行情/持仓变化 → 刷新所有行(买卖行自身也会刷)
	StockManager.prices_updated.connect(_refresh_rows)
	StockManager.holdings_changed.connect(func(_i): _refresh_rows())

	# 默认选中第一支(省去"点击选择"提示)
	if _rows.is_empty():
		_update_detail()
	else:
		_on_selected(0)

# 语言切换:行名/详情重刷(StockRow 里的按钮文字由它自己处理)
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_rows()
		_update_detail()

func _refresh_rows() -> void:
	for r in _rows:
		r.refresh()
	_update_detail()

func _on_selected(index: int) -> void:
	_selected = index
	for r in _rows:
		r.set_selected(r.index == index)
	buy_row.set_stock(index)
	sell_row.set_stock(index)
	_update_detail()

# 详情读数:名字 · 持仓 N 股 · 成本 · 现价 · 盈亏(带色)
func _update_detail() -> void:
	if _selected < 0 or _selected >= _rows.size():
		detail.text = "[color=#999999]%s[/color]" % tr("STOCK_HINT_PICK")
		return
	var i := _selected
	var disp_name := StockManager.get_display_name(i)
	var held := StockManager.get_holdings(i)
	var price := StockManager.get_price(i)
	if held <= 0:
		detail.text = "[b]%s[/b]\n%s %d" % [disp_name, tr("STOCK_LB_PRICE"), price]
		return
	var cost := StockManager.get_avg_cost(i)
	var profit := StockManager.get_profit(i)
	var pl_hex := "#3fb950" if profit > 0 else ("#f85149" if profit < 0 else "#999999")
	var pl_sign := "+" if profit > 0 else ""
	detail.text = "[b]%s[/b]\n%s %d %s · %s %.1f · %s %d · %s [color=%s]%s%d[/color]" % [
		disp_name,
		tr("STOCK_LB_HELD"), held, tr("STOCK_LB_SHARES"),
		tr("STOCK_LB_COST"), cost,
		tr("STOCK_LB_PRICE"), price,
		tr("STOCK_LB_PL"), pl_hex, pl_sign, profit
	]
