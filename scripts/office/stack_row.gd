#stack_row.gd
extends Button
class_name StockRow

signal selected(index: int)

# 同一个 StackRow:在 Inspector 的下拉里选它是「数据行」还是「表头」。
# 表头模式 = 只显示列标题(公司/现价/持仓/盈亏),不读股票数据、不染色、不可点。
enum Kind { DATA, HEADER }
@export var kind: Kind = Kind.DATA

@onready var name_label: Label = $MarginContainer/Columns/Name
@onready var price_label: Label = $MarginContainer/Columns/Price
@onready var held_label: Label = $MarginContainer/Columns/Held
@onready var pl_label: Label = $MarginContainer/Columns/PL
@onready var normal_bcg: NinePatchRect = $HilightBcg    # 非选中背景
@onready var hilight_bcg: NinePatchRect = $NormalBcg # 选中背景

# 刻板印象:红涨绿跌
const COL_UP := Color(0.80, 0.12, 0.12)    # 涨 = 红
const COL_DOWN := Color(0.09, 0.48, 0.18)  # 跌 = 绿
const COL_FLAT := Color(0.18, 0.18, 0.18)  # 平 = 深灰(别用浅灰,彩色底上会显得半透明)

var index: int = -1

func _ready() -> void:
	# 背景图必须鼠标穿透,否则会盖在按钮上挡住点击 → 选不中
	normal_bcg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hilight_bcg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if kind == Kind.HEADER:
		mouse_filter = Control.MOUSE_FILTER_IGNORE   # 表头不可点、不响应悬停
		normal_bcg.hide()                            # 表头不要背景框
		hilight_bcg.hide()
		_apply_header()
		return
	pressed.connect(func(): selected.emit(index))

# 语言切换时,表头标题重刷(数据行的名字由 refresh() 负责)
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and kind == Kind.HEADER:
		_apply_header()

# 表头模式:四列填列标题,清掉染色,保持你在场景里设的字体/颜色
func _apply_header() -> void:
	name_label.text = tr("STOCK_LB_NAME")
	price_label.text = tr("STOCK_LB_PRICE")
	held_label.text = tr("STOCK_LB_HELD")
	pl_label.text = tr("STOCK_LB_PL")
	# 表头文字底对齐
	for l in [name_label, price_label, held_label, pl_label]:
		l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

func setup(i: int) -> void:
	if kind == Kind.HEADER:
		_apply_header()
		return
	index = i
	refresh()

func refresh() -> void:
	if kind == Kind.HEADER:
		_apply_header()
		return
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
	if kind == Kind.HEADER:
		return
	hilight_bcg.visible = on
	normal_bcg.visible = not on
