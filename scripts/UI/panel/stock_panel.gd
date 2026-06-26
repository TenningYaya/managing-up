# stock_panel.gd —— 炒股交易页
# 配合场景结构:
#   Control(本脚本)
#   └─ StockContainer (VBoxContainer)
#       ├─ StockList     (VBoxContainer) ← 代码往这里塞「表头 + 4 行股票」(每行=Button)
#       ├─ RichTextLabel                  ← 选中股票的详情读数(持有/成本/现价/盈亏)
#       ├─ BuyRow        (TradeRow)
#       └─ SellRow       (TradeRow)
extends Control

# 列宽 / 行高 / 间距(随便调)
const ROW_H := 28
const PRICE_W := 58
const HOLD_W := 48
const PL_W := 56
const SEP := 6

# 红涨绿跌(刻板印象)。都是实色高对比 —— 浅灰会在彩色底上显得"半透明",别用。
# 颜色按你最终的背景再调。
const COL_UP := Color(0.80, 0.12, 0.12)    # 涨 = 红
const COL_DOWN := Color(0.09, 0.48, 0.18)  # 跌 = 绿
const COL_FLAT := Color(0.18, 0.18, 0.18)  # 平 = 深灰(别用浅灰)

@onready var stock_list: VBoxContainer = $StockContainer/StockList
@onready var detail: RichTextLabel = $StockContainer/RichTextLabel
@onready var buy_row: TradeRow = $StockContainer/BuyRow
@onready var sell_row: TradeRow = $StockContainer/SellRow

var _header_cells: Array = []
var _rows: Array = []                   # 每项 { btn, name, price, hold, pl, hl }
var _selected: int = -1

func _ready() -> void:
	# 详情读数
	detail.bbcode_enabled = true
	detail.fit_content = true
	detail.scroll_active = false

	# 上半:把「表头 + 股票行」建进 StockList
	_build_header()
	for i in range(StockManager.get_stock_count()):
		var row := _make_row(i)
		stock_list.add_child(row.btn)
		_rows.append(row)

	# 下半:买/卖两行定模式(BuyRow/SellRow 是 trade_row 实例)
	buy_row.set_mode(TradeRow.Mode.BUY)
	sell_row.set_mode(TradeRow.Mode.SELL)

	# 行情/持仓变化 → 刷新列表(买卖行自身也会刷)
	StockManager.prices_updated.connect(_refresh)
	StockManager.holdings_changed.connect(func(_i): _refresh())

	_refresh()
	_update_detail()

# 语言切换:重刷表头 + 列表 + 详情(买卖按钮由 normal_button 自己刷)
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		if _header_cells.size() == 4:
			_header_cells[0].text = tr("STOCK_LB_NAME")
			_header_cells[1].text = tr("STOCK_LB_PRICE")
			_header_cells[2].text = tr("STOCK_LB_HELD")
			_header_cells[3].text = tr("STOCK_LB_PL")
		_refresh()

# ==========================================================
# 表头
# ==========================================================
func _build_header() -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", SEP)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := _hcell(tr("STOCK_LB_NAME"), 0, HORIZONTAL_ALIGNMENT_LEFT, true)
	var p := _hcell(tr("STOCK_LB_PRICE"), PRICE_W, HORIZONTAL_ALIGNMENT_RIGHT, false)
	var hd := _hcell(tr("STOCK_LB_HELD"), HOLD_W, HORIZONTAL_ALIGNMENT_RIGHT, false)
	var pl := _hcell(tr("STOCK_LB_PL"), PL_W, HORIZONTAL_ALIGNMENT_RIGHT, false)
	h.add_child(n)
	h.add_child(p)
	h.add_child(hd)
	h.add_child(pl)
	_header_cells = [n, p, hd, pl]
	stock_list.add_child(h)

func _hcell(text: String, w: int, align: int, expand: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.modulate = Color(1, 1, 1, 1.0)   # 表头透明度(想淡就把 alpha 调小,如 0.85)
	if expand:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		l.custom_minimum_size.x = w
	return l

# ==========================================================
# 股票行(每行=Button,列是子节点,Label 全 IGNORE → 点击穿到整行)
# ==========================================================
func _make_row(index: int) -> Dictionary:
	var btn := Button.new()
	btn.flat = true
	btn.custom_minimum_size.y = ROW_H
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_on_row_pressed.bind(index))

	var hl := ColorRect.new()
	hl.color = Color(1, 1, 1, 0.18)
	hl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hl.visible = false
	btn.add_child(hl)

	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.add_theme_constant_override("separation", SEP)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(h)

	var name_l := _cell(0, HORIZONTAL_ALIGNMENT_LEFT, true)
	var price_l := _cell(PRICE_W, HORIZONTAL_ALIGNMENT_RIGHT, false)
	var hold_l := _cell(HOLD_W, HORIZONTAL_ALIGNMENT_RIGHT, false)
	var pl_l := _cell(PL_W, HORIZONTAL_ALIGNMENT_RIGHT, false)
	h.add_child(name_l)
	h.add_child(price_l)
	h.add_child(hold_l)
	h.add_child(pl_l)

	return { "btn": btn, "name": name_l, "price": price_l, "hold": hold_l, "pl": pl_l, "hl": hl }

func _cell(w: int, align: int, expand: bool) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_vertical = Control.SIZE_FILL
	if expand:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		l.custom_minimum_size.x = w
	return l

# ==========================================================
# 刷新
# ==========================================================
func _refresh() -> void:
	for i in range(_rows.size()):
		var r = _rows[i]
		r.name.text = StockManager.get_display_name(i)
		r.price.text = str(StockManager.get_price(i))
		var held := StockManager.get_holdings(i)
		r.hold.text = str(held)
		r.pl.text = _pl_text(i, held)
		_color_row(r, i)
	_update_detail()

# 整行按涨跌染色(红涨绿跌)。基准=相对上一次行情(get_trend);想换成相对成本/中枢自行替换。
func _color_row(r: Dictionary, index: int) -> void:
	var trend := StockManager.get_trend(index)
	var c := COL_FLAT
	if trend > 0:
		c = COL_UP
	elif trend < 0:
		c = COL_DOWN
	for l in [r.name, r.price, r.hold, r.pl]:
		l.add_theme_color_override("font_color", c)

func _pl_text(index: int, held: int) -> String:
	if held <= 0:
		return "—"
	var p := StockManager.get_profit(index)
	return ("+" + str(p)) if p > 0 else str(p)

func _on_row_pressed(index: int) -> void:
	_selected = index
	for i in range(_rows.size()):
		_rows[i].hl.visible = (i == index)
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
		detail.text = "[b]%s[/b]   %s %d" % [disp_name, tr("STOCK_LB_PRICE"), price]
		return
	var cost := StockManager.get_avg_cost(i)
	var profit := StockManager.get_profit(i)
	var pl_hex := "#3fb950" if profit > 0 else ("#f85149" if profit < 0 else "#999999")
	var pl_sign := "+" if profit > 0 else ""
	detail.text = "[b]%s[/b]   %s %d %s · %s %.1f · %s %d · %s [color=%s]%s%d[/color]" % [
		disp_name,
		tr("STOCK_LB_HELD"), held, tr("STOCK_LB_SHARES"),
		tr("STOCK_LB_COST"), cost,
		tr("STOCK_LB_PRICE"), price,
		tr("STOCK_LB_PL"), pl_hex, pl_sign, profit
	]
