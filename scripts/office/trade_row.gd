extends HBoxContainer
class_name TradeRow

enum Mode { BUY, SELL }
@export var mode: Mode = Mode.BUY

# ⚠️ ActionButton / AllButton 是预制的 normal_button(TextureButton 子类),
#    没有 .text,要用它的 button_text(传翻译 key,normal_button 内部会 tr() 并随语言自刷)。
#    所以这两个引用必须"不写类型"(动态访问 button_text),否则静态类型检查会报错。
@onready var action_btn = $ActionButton
@onready var slider: HSlider = $AmountSlider
@onready var info_label: Label = $InfoLabel
@onready var all_btn = $AllButton

var _index: int = -1   # 当前选中的股票
var qty_tag: Label     # 跟着滑条抓手跑的"股数"小标签(代码创建)

func _ready() -> void:
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = 0
	slider.value_changed.connect(func(_v): _update_info())
	slider.resized.connect(_position_qty_tag)   # 滑条尺寸变了要重新定位
	_setup_qty_tag()
	action_btn.pressed.connect(_on_action)
	all_btn.pressed.connect(_on_all)
	# 行情/持仓变了,可买可卖量会变,自己刷新
	StockManager.prices_updated.connect(_update_info)
	StockManager.holdings_changed.connect(func(_i): _update_info())
	_apply_mode_texts()
	_update_info()

# 语言切换:按钮文字由 normal_button 自己刷;这里只刷 InfoLabel 里的"股"
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_info()

# 面板在 _ready 里调用,确定本行是买还是卖
func set_mode(m: int) -> void:
	mode = m
	_apply_mode_texts()
	_update_info()

# 选股切换时面板调它
func set_stock(index: int) -> void:
	_index = index
	slider.value = 0
	_update_info()

func _apply_mode_texts() -> void:
	# normal_button.button_text 接收翻译 key,内部 tr() 并随语言自动刷新
	action_btn.button_text = "STOCK_BTN_BUY" if mode == Mode.BUY else "STOCK_BTN_SELL"
	all_btn.button_text = "STOCK_BTN_BUYALL" if mode == Mode.BUY else "STOCK_BTN_SELLALL"

# 当前模式下"最多能操作多少股"
func _max_amount() -> int:
	if _index < 0:
		return 0
	return StockManager.get_buyable(_index) if mode == Mode.BUY else StockManager.get_sellable(_index)

func _current_qty() -> int:
	return int(floor(_max_amount() * slider.value / 100.0))

func _update_info() -> void:
	var qty := _current_qty()
	var price := StockManager.get_price(_index) if _index >= 0 else 0
	# 股数:小标签,贴在滑条抓手正上方,跟着抓手移动
	if is_instance_valid(qty_tag):
		qty_tag.text = "%d" % [qty]
		_position_qty_tag()
	# 旁边的 InfoLabel 现在只显示这笔交易的 KPI(股数已移到抓手上)
	info_label.text = "%d KPI" % (qty * price)
	var has_any := _max_amount() > 0
	action_btn.disabled = (not has_any) or qty <= 0
	all_btn.disabled = not has_any

# 创建跟随滑条抓手的"股数"小标签(挂在滑条下,绝对定位,不挡点击)
func _setup_qty_tag() -> void:
	qty_tag = Label.new()
	qty_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	qty_tag.add_theme_font_size_override("font_size", 14)   # 缩小一点
	slider.add_child(qty_tag)

# 按当前 value 算出抓手中心 x,把标签摆到抓手正上方
func _position_qty_tag() -> void:
	if not is_instance_valid(qty_tag):
		return
	var rng := slider.max_value - slider.min_value
	var ratio := 0.0 if rng <= 0.0 else (slider.value - slider.min_value) / rng
	# 抓手在轨道两端各占半个自身宽,可移动范围 = 轨道宽 - 一个抓手宽
	var grab_w := 0.0
	if slider.has_theme_icon("grabber"):
		grab_w = float(slider.get_theme_icon("grabber").get_width())
	var usable := maxf(0.0, slider.size.x - grab_w)
	var center_x := grab_w * 0.5 + ratio * usable
	qty_tag.reset_size()   # 让 size 跟文字走,才能正确居中
	qty_tag.position = Vector2(center_x - qty_tag.size.x * 0.5, -qty_tag.size.y - 2.0)

func _on_action() -> void:
	var qty := _current_qty()
	if _index < 0 or qty <= 0:
		return
	if mode == Mode.BUY:
		StockManager.buy(_index, qty)
	else:
		StockManager.sell(_index, qty)
	slider.value = 0   # 操作完归零;StockManager 会发信号触发刷新

# 全买/全卖:二次确认
func _on_all() -> void:
	if _index < 0 or _max_amount() <= 0:
		return
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = tr("STOCK_CONFIRM_BUYALL") if mode == Mode.BUY else tr("STOCK_CONFIRM_SELLALL")
	dlg.ok_button_text = tr("STOCK_BTN_CONFIRM")
	dlg.get_cancel_button().text = tr("STOCK_BTN_CANCEL")
	add_child(dlg)
	dlg.confirmed.connect(func():
		if mode == Mode.BUY:
			StockManager.buy_all(_index)
		else:
			StockManager.sell_all(_index)
		slider.value = 0
	)
	# 关掉就销毁,别留垃圾
	dlg.canceled.connect(dlg.queue_free)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.popup_centered()
