# stock_manager.gd —— 炒股办公室 · 全局股市核心（autoload 单例）
# ------------------------------------------------------------------
# 设计要点（来自会议决策）：
#   1. 用 KPI 炒 KPI：买卖都走 Gamemanager 的 KPI，本脚本不碰美金。
#   2. 四支股票，每 60 秒变动一次；各有性格（稳/浪由 volatility + reversion 决定）。
#   3. 行情永远运行（不停盘）。炒股办公室只负责“能不能交易 + 分红”，与本脚本解耦——
#      分红逻辑写在 StockOfficeLogic 里，不在这里。
#   4. 补货上限：每支股票每 30 分钟最多买 BASE_WINDOW_CAP 股，到点回满。
#      卖出补偿：卖掉 n 股后，临时额外获得 +n 的可买额度，撑过“下一分钟”，
#      “下下一分钟”恢复正常（用行情 tick 次数判定，见 BUYBACK_GRACE_TICKS）。
#   5. 无交易冷却，随时买卖。
#   6. 持仓上限很高（前期 KPI 根本买不到这么多），真正的前期约束是“买得起 + 补货上限”。
#
# 本地化：股票名只存翻译 key（STOCK_*），UI 用 tr() 取名。建议在 CSV 里登记：
#   STOCK_996  → 中:996福报科技      英:996 Blessing Tech
#   STOCK_PIE  → 中:画饼集团          英:Pie-in-the-Sky Group
#   STOCK_LEEK → 中:韭菜农业          英:Leek Agriculture
#   STOCK_FISH → 中:摸鱼网络          英:Slacker Network
# ------------------------------------------------------------------
extends Node

# ============================================================
# 信号（交易页签监听这些来刷新 UI）
# ============================================================
signal prices_updated                   # 每次行情 tick 后（价格已更新）
signal holdings_changed(index: int)     # 某支股票持仓变化（买/卖之后）
signal restock_window_reset             # 补货周期重置（常规额度回满）

# ============================================================
# 可调参数（测试期只改这里）
# ============================================================
const PRICE_TICK_SECONDS := 60.0        # 行情多久变一次
const RESTOCK_WINDOW_SECONDS := 1800.0  # 补货周期：30 分钟
const BASE_WINDOW_CAP := 1000           # 每支每个补货周期的常规购买上限
const HOLDING_CAP := 1_000_000          # 单支持仓上限（很高，前期摸不到）
const PRICE_MIN := 1                     # 股价地板，永不低于此
# 卖出后额外额度保留的“行情次数”：撑过下一次变动，下下一次变动时恢复。
#   例：还剩 20 秒变动时卖出 → 这 20 秒 + 下一整分钟内可买 1000+n；再下一分钟恢复 1000。
const BUYBACK_GRACE_TICKS := 2

# ============================================================
# 单支股票数据（内部类）
# ============================================================
class StockData:
	var name_key: String                # 本地化 key（UI 用 tr() 取名）
	var center: float                   # 均值回归中枢
	var volatility: float               # 单次波动幅度（相对中枢的比例）
	var reversion: float                # 回归强度 0~1（越大越粘着中枢、越稳）
	var price: float                    # 当前价（浮点，内部用；对外 round 成整数）
	var prev_price: float               # 上一 tick 的价（算涨跌指示用）
	var holdings: int = 0               # 玩家持仓股数
	var avg_cost: float = 0.0           # 加权平均成本（KPI/股），用于算浮动盈亏
	var bought_this_window: int = 0     # 本补货周期已买（计入常规上限）
	var buyback_bonus: int = 0          # 卖出带来的临时额外可买额度
	var buyback_expire_tick: int = -1   # 该额度在“第几个行情 tick”失效

# ============================================================
# 运行时状态
# ============================================================
var stocks: Array = []                  # Array[StockData]
var _price_accum := 0.0                 # 距下次行情变动的累计秒数
var _restock_accum := 0.0               # 距下次补货重置的累计秒数
var _tick_count := 0                    # 行情已变动的总次数（给 buyback 过期判定用）

# ============================================================
# 初始化
# ============================================================
func _ready() -> void:
	_init_stocks()

func _init_stocks() -> void:
	# _make(翻译key, 中枢价, 波动比例, 回归强度)
	stocks = [
		_make("STOCK_996", 100.0, 0.025, 0.15),  # 996福报科技：蓝筹，较稳，强回归
		_make("STOCK_PIE",  50.0, 0.080, 0.04),  # 画饼集团：妖股，浪，弱回归（爱炒预期、爱跑远）
		_make("STOCK_LEEK", 30.0, 0.110, 0.08),  # 韭菜农业：镰刀股，最浪，专坑散户
		_make("STOCK_FISH", 60.0, 0.015, 0.20),  # 摸鱼网络：躺平股，几乎不动
	]

func _make(key: String, center: float, vol: float, rev: float) -> StockData:
	var s := StockData.new()
	s.name_key = key
	s.center = center
	s.volatility = vol
	s.reversion = rev
	s.price = center
	s.prev_price = center
	return s

# ============================================================
# 行情与补货计时（行情永远走）
# ============================================================
func _process(delta: float) -> void:
	_price_accum += delta
	if _price_accum >= PRICE_TICK_SECONDS:
		_price_accum -= PRICE_TICK_SECONDS
		_tick_prices()

	_restock_accum += delta
	if _restock_accum >= RESTOCK_WINDOW_SECONDS:
		_restock_accum -= RESTOCK_WINDOW_SECONDS
		_reset_restock_window()

# 均值回归随机游走：price += 回归项 + 噪声项
func _tick_prices() -> void:
	_tick_count += 1
	for s in stocks:
		s.prev_price = s.price
		var drift: float = s.reversion * (s.center - s.price)
		var noise: float = s.center * s.volatility * randf_range(-1.0, 1.0)
		s.price = maxf(float(PRICE_MIN), s.price + drift + noise)
		# 清理过期的“卖出回购额度”
		if s.buyback_bonus > 0 and _tick_count >= s.buyback_expire_tick:
			s.buyback_bonus = 0
			s.buyback_expire_tick = -1
	prices_updated.emit()

func _reset_restock_window() -> void:
	for s in stocks:
		s.bought_this_window = 0
	restock_window_reset.emit()

# 当前仍然有效的卖出回购额度（过期返回 0）
func _active_buyback(s: StockData) -> int:
	if s.buyback_bonus > 0 and _tick_count < s.buyback_expire_tick:
		return s.buyback_bonus
	return 0

# ============================================================
# 交易 API（供 UI 调用）
# ============================================================

# 当前还能买多少股：受「买得起 / 补货上限+回购额度 / 持仓上限」三重约束取最小
func get_buyable(index: int) -> int:
	if index < 0 or index >= stocks.size():
		return 0
	var s: StockData = stocks[index]
	var price := get_price(index)
	if price <= 0:
		return 0
	var by_kpi := Gamemanager.kpi / price                       # 整数除：买得起多少股
	var by_cap := maxi(0, BASE_WINDOW_CAP - s.bought_this_window) + _active_buyback(s)
	var by_holding := maxi(0, HOLDING_CAP - s.holdings)
	return mini(mini(by_kpi, by_cap), by_holding)

# 当前可卖（= 持仓）
func get_sellable(index: int) -> int:
	if index < 0 or index >= stocks.size():
		return 0
	return stocks[index].holdings

# 买入 qty 股；成功返回 true（KPI 不足 / 超过可买量都会失败）
func buy(index: int, qty: int) -> bool:
	if qty <= 0 or index < 0 or index >= stocks.size():
		return false
	var s: StockData = stocks[index]
	var price := get_price(index)
	if price <= 0 or qty > get_buyable(index):
		return false
	var cost := price * qty
	if not Gamemanager.spend_kpi(cost, Ledger.Cat.STOCK_BUY):
		return false
	# 先消耗常规补货额度，超出部分由“卖出回购额度”兜底（这样能买到 1000+n）
	var from_window := mini(qty, maxi(0, BASE_WINDOW_CAP - s.bought_this_window))
	s.bought_this_window += from_window
	var from_bonus := qty - from_window
	if from_bonus > 0:
		s.buyback_bonus = maxi(0, s.buyback_bonus - from_bonus)
	# 加权平均成本：买入按现价摊入（此刻 s.holdings 仍是买入前的数量）
	s.avg_cost = (s.holdings * s.avg_cost + qty * price) / float(s.holdings + qty)
	s.holdings += qty
	holdings_changed.emit(index)
	return true

# 卖出 qty 股；成功返回 true
func sell(index: int, qty: int) -> bool:
	if qty <= 0 or index < 0 or index >= stocks.size():
		return false
	var s: StockData = stocks[index]
	if qty > s.holdings:
		return false
	var price := get_price(index)
	# 卖股净利润 =（现价 − 持仓均价）× 股数，趁 avg_cost 清零前算好，传给记账显示
	var net_profit := int(round((price - s.avg_cost) * qty))
	s.holdings -= qty
	Gamemanager.add_kpi(price * qty, Ledger.Cat.STOCK_SELL, null, net_profit)
	# 清仓后成本归零（移动平均成本法：卖出不改均价，清空后重新计）
	if s.holdings <= 0:
		s.holdings = 0
		s.avg_cost = 0.0
	# 卖出 → 给临时回购额度（可叠加），并刷新过期时间（撑过下一分钟，下下分钟恢复）
	s.buyback_bonus += qty
	s.buyback_expire_tick = _tick_count + BUYBACK_GRACE_TICKS
	holdings_changed.emit(index)
	return true

# 全部购买：用当前全部 KPI 买；撞补货上限就买到上限为止（含回购额度）
func buy_all(index: int) -> bool:
	return buy(index, get_buyable(index))

# 全部售出
func sell_all(index: int) -> bool:
	return sell(index, get_sellable(index))

# 按“当前可买量的百分比”买入（slider 用）。pct 取 0.0~1.0
func buy_percent(index: int, pct: float) -> bool:
	var qty := int(floor(get_buyable(index) * clampf(pct, 0.0, 1.0)))
	return buy(index, qty)

# 按“当前持仓的百分比”卖出（slider 用）。pct 取 0.0~1.0
func sell_percent(index: int, pct: float) -> bool:
	var qty := int(floor(get_sellable(index) * clampf(pct, 0.0, 1.0)))
	return sell(index, qty)

# ============================================================
# 查询 API（UI 显示用，不画折线，只给数值/涨跌）
# ============================================================
func get_stock_count() -> int:
	return stocks.size()

func get_display_name(index: int) -> String:
	if index < 0 or index >= stocks.size():
		return ""
	return tr(stocks[index].name_key)

func get_price(index: int) -> int:
	if index < 0 or index >= stocks.size():
		return 0
	return maxi(PRICE_MIN, int(round(stocks[index].price)))

func get_prev_price(index: int) -> int:
	if index < 0 or index >= stocks.size():
		return 0
	return maxi(PRICE_MIN, int(round(stocks[index].prev_price)))

# 涨跌指示：1 涨 / -1 跌 / 0 平（替代折线图）
func get_trend(index: int) -> int:
	return signi(get_price(index) - get_prev_price(index))

func get_holdings(index: int) -> int:
	if index < 0 or index >= stocks.size():
		return 0
	return stocks[index].holdings

# 当前持仓按现价的市值
func get_holding_value(index: int) -> int:
	return get_price(index) * get_holdings(index)

# 加权平均成本（KPI/股，浮点，UI 自行格式化小数）
func get_avg_cost(index: int) -> float:
	if index < 0 or index >= stocks.size():
		return 0.0
	return stocks[index].avg_cost

# 浮动盈亏（KPI，已取整）：(现价 - 均价) × 持仓
func get_profit(index: int) -> int:
	if index < 0 or index >= stocks.size():
		return 0
	var s: StockData = stocks[index]
	return int(round((get_price(index) - s.avg_cost) * s.holdings))

# 本周期剩余常规额度（不含回购加成），UI 可用来提示“还能补货多少”
func get_window_room(index: int) -> int:
	if index < 0 or index >= stocks.size():
		return 0
	return maxi(0, BASE_WINDOW_CAP - stocks[index].bought_this_window)

# 距下次行情变动 / 下次补货重置的剩余秒数（UI 倒计时用）
func get_seconds_to_next_tick() -> float:
	return maxf(0.0, PRICE_TICK_SECONDS - _price_accum)

func get_seconds_to_restock() -> float:
	return maxf(0.0, RESTOCK_WINDOW_SECONDS - _restock_accum)

# ============================================================
# 存档 / 读档 / 删档（供 SaveManager 之后接线调用）
# ============================================================
func to_save_dict() -> Dictionary:
	var arr := []
	for s in stocks:
		arr.append({
			"price": s.price,
			"prev_price": s.prev_price,
			"holdings": s.holdings,
			"avg_cost": s.avg_cost,
			"bought_this_window": s.bought_this_window,
			"buyback_bonus": s.buyback_bonus,
			"buyback_expire_tick": s.buyback_expire_tick,
		})
	return {
		"stocks": arr,
		"tick_count": _tick_count,
		"price_accum": _price_accum,
		"restock_accum": _restock_accum,
	}

func load_from_dict(data: Dictionary) -> void:
	if data == null or data.is_empty():
		return
	_tick_count = int(data.get("tick_count", 0))
	_price_accum = float(data.get("price_accum", 0.0))
	_restock_accum = float(data.get("restock_accum", 0.0))
	var arr: Array = data.get("stocks", [])
	for i in range(mini(arr.size(), stocks.size())):
		var d: Dictionary = arr[i]
		var s: StockData = stocks[i]
		s.price = float(d.get("price", s.center))
		s.prev_price = float(d.get("prev_price", s.price))
		s.holdings = int(d.get("holdings", 0))
		s.avg_cost = float(d.get("avg_cost", 0.0))
		s.bought_this_window = int(d.get("bought_this_window", 0))
		s.buyback_bonus = int(d.get("buyback_bonus", 0))
		s.buyback_expire_tick = int(d.get("buyback_expire_tick", -1))
	prices_updated.emit()
	for i in range(stocks.size()):
		holdings_changed.emit(i)

# 删档复位：价格回中枢、持仓清零、计时归零
func reset_to_default() -> void:
	_tick_count = 0
	_price_accum = 0.0
	_restock_accum = 0.0
	_init_stocks()
	prices_updated.emit()
