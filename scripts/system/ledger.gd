# ledger.gd —— 会计 / 记账系统（autoload 单例）
# 所有 KPI / 美金的收支都经 Gamemanager 的 add_/spend_ 汇入这里，按“来源大类”和“天”聚合。
# 设计要点：数据全部封顶——
#   · 生涯累计 lifetime：每个来源一个有符号总额（收入正、支出负）
#   · 每日汇总 daily_summary：每天每来源一个净额，最多 SUMMARY_DAYS 天
#   · 每日详情 daily_detail：每天按“员工”聚合，最多 DETAIL_DAYS 天（超过就点不开）
# 进行中的当天(_cur_*)实时累加，且随存档保留（读档不清零）。
extends Node

enum Cur { KPI = 0, DOLLAR = 1 }

# ⚠️ 只能在末尾追加新来源，绝不可重排 / 删除（存档按 int 记）。加新项：追加枚举 + 补 CAT_META 一行。
enum Cat {
	WORK_OUTPUT,     # KPI 收入 · 员工文件产出
	WORK_INTERRUPT,  # KPI 收入 · 员工打断补偿
	DECOR_SELL,      # KPI 收入 · 变卖家具
	STOCK_SELL,      # KPI 收入 · 卖出股票
	HIRE_KPI,        # KPI 支出 · 招聘
	DESK_UPGRADE,    # KPI 支出 · 工位升级
	RANK_UPGRADE,    # KPI 支出 · 员工升级
	BUILD_DECOR,     # KPI 支出 · 建造与装修
	STOCK_BUY,       # KPI 支出 · 买入股票
	WORK_BONUS,      # 美金收入 · 员工文件产出奖金
	SLACK_REWARD,    # 美金收入 · 摸鱼挽回损失
	STOCK_DIVIDEND,  # 美金收入 · 股票分红
	HEADHUNT,        # 美金支出 · 猎头招聘
	OTHER
}

# 每个来源的元数据：属于哪种货币 / 是收入还是支出 / 能否点开(员工级详情) / 本地化 key。
# UI 与统计都读这张表，加新来源只改这里，天然可扩展。
const CAT_META := {
	Cat.WORK_OUTPUT:    {"cur": Cur.KPI,    "income": true,  "expandable": true,  "key": "LEDGER_WORK_OUTPUT"},
	Cat.WORK_INTERRUPT: {"cur": Cur.KPI,    "income": true,  "expandable": true,  "key": "LEDGER_WORK_INTERRUPT", "hidden": true},   # 已并入员工产出：不在下拉单列（仅兼容旧存档残留数据）
	Cat.DECOR_SELL:     {"cur": Cur.KPI,    "income": true,  "expandable": false, "key": "LEDGER_DECOR_SELL"},
	Cat.STOCK_SELL:     {"cur": Cur.KPI,    "income": true,  "expandable": false, "key": "LEDGER_STOCK_SELL"},
	Cat.HIRE_KPI:       {"cur": Cur.KPI,    "income": false, "expandable": false, "key": "LEDGER_HIRE_KPI"},
	Cat.DESK_UPGRADE:   {"cur": Cur.KPI,    "income": false, "expandable": false, "key": "LEDGER_DESK_UPGRADE"},
	Cat.RANK_UPGRADE:   {"cur": Cur.KPI,    "income": false, "expandable": false, "key": "LEDGER_RANK_UPGRADE"},
	Cat.BUILD_DECOR:    {"cur": Cur.KPI,    "income": false, "expandable": false, "key": "LEDGER_BUILD_DECOR"},
	Cat.STOCK_BUY:      {"cur": Cur.KPI,    "income": false, "expandable": false, "key": "LEDGER_STOCK_BUY"},
	Cat.WORK_BONUS:     {"cur": Cur.DOLLAR, "income": true,  "expandable": true,  "key": "LEDGER_WORK_BONUS"},
	Cat.SLACK_REWARD:   {"cur": Cur.DOLLAR, "income": true,  "expandable": false, "key": "LEDGER_SLACK_REWARD"},
	Cat.STOCK_DIVIDEND: {"cur": Cur.DOLLAR, "income": true,  "expandable": false, "key": "LEDGER_STOCK_DIVIDEND"},
	Cat.HEADHUNT:       {"cur": Cur.DOLLAR, "income": false, "expandable": false, "key": "LEDGER_HEADHUNT"},
	Cat.OTHER:          {"cur": Cur.KPI,    "income": true,  "expandable": false, "key": "LEDGER_OTHER"},
}

const DAY_LENGTH := 600.0   # 600 秒游戏时间 = 一天（以后接昼夜系统就改成它触发 settle_day）
const DETAIL_DAYS := 10     # 员工级详情保留天数
const SUMMARY_DAYS := 30    # 每日汇总保留天数

# —— 生涯累计 ——
var lifetime := {}          # {cat_int: 有符号总额}
# —— 进行中的当天（实时、随存档保留）——
var _cur_day := 0
var _cur_cats := {}         # {cat_int: 当天净额}
var _cur_emp := {}          # {uid: {"name":String, "kpi":int, "dollar":int, "files":int}}
var _cur_stock_net := 0     # 当天卖股净利润合计
# —— 已结算历史 ——
var daily_summary := []     # [{"day":int, "cats":{cat_int:net}}]，最多 SUMMARY_DAYS，旧的在前
var daily_detail := []      # [{"day":int, "emp":{uid:{...}}, "stock_net":int}]，最多 DETAIL_DAYS

# —— 员工进账窗口用（与“天”无关，全局）——
const RECENT_EMP_EVENTS_CAP := 100
var lifetime_emp := {}        # {uid: {"name":String, "kpi":int, "dollar":int}}  生涯每员工累计（“总计”模式）
var recent_emp_events := []   # [{"uid":int, "name":String, "cur":int, "amount":int}]  最近进账事件（“实时/按次”模式），旧的在前

signal ledger_changed       # 有新交易 / 结算时发出，UI 据此刷新（UI 侧自行节流）


func _process(_dt: float) -> void:
	var d := int(Gamemanager.total_time / DAY_LENGTH)
	while _cur_day < d:
		settle_day(_cur_day)
		_cur_day += 1


# 核心记账入口：Gamemanager 的 add_/spend_ 在“交易成功”时调用。
# delta：收入为正、支出为负。emp：员工类收入时传入员工节点（用于当天员工级明细）。meta：卖股时传净利润。
func record(cur: int, cat: int, delta: int, emp = null, meta: int = 0) -> void:
	if cat < 0:
		cat = Cat.OTHER   # -1 哨兵（未指定来源）归一为 OTHER
	lifetime[cat] = int(lifetime.get(cat, 0)) + delta
	_cur_cats[cat] = int(_cur_cats.get(cat, 0)) + delta

	if emp != null and is_instance_valid(emp):
		var uid := 0
		if emp.get("uid") != null:
			uid = int(emp.get("uid"))
		var emp_name: String = emp.get_display_name() if emp.has_method("get_display_name") else str(uid)

		# a) 当天按员工明细（每日详情用）
		var row: Dictionary = _cur_emp.get(uid, {"name": "", "kpi": 0, "dollar": 0, "files": 0})
		row["name"] = emp_name
		if cur == Cur.KPI:
			row["kpi"] = int(row["kpi"]) + delta
		else:
			row["dollar"] = int(row["dollar"]) + delta
		if cat == Cat.WORK_OUTPUT:
			row["files"] = int(row["files"]) + 1
		_cur_emp[uid] = row

		# b) 生涯每员工累计（员工窗口“总计”模式用）
		var lt: Dictionary = lifetime_emp.get(uid, {"name": emp_name, "kpi": 0, "dollar": 0})
		lt["name"] = emp_name
		if cur == Cur.KPI:
			lt["kpi"] = int(lt["kpi"]) + delta
		else:
			lt["dollar"] = int(lt["dollar"]) + delta
		lifetime_emp[uid] = lt

		# c) 最近进账事件（员工窗口“实时/按次”模式用），环形封顶，天然不吃算力
		recent_emp_events.append({"uid": uid, "name": emp_name, "cur": cur, "amount": delta})
		while recent_emp_events.size() > RECENT_EMP_EVENTS_CAP:
			recent_emp_events.pop_front()

	if cat == Cat.STOCK_SELL:
		_cur_stock_net += meta

	ledger_changed.emit()


# 结算一天：把当天累加器定格进汇总/详情两个环形缓冲，然后清零。
func settle_day(day: int) -> void:
	daily_summary.append({"day": day, "cats": _cur_cats.duplicate(true)})
	while daily_summary.size() > SUMMARY_DAYS:
		daily_summary.pop_front()

	daily_detail.append({"day": day, "emp": _cur_emp.duplicate(true), "stock_net": _cur_stock_net})
	while daily_detail.size() > DETAIL_DAYS:
		daily_detail.pop_front()

	_cur_cats.clear()
	_cur_emp.clear()
	_cur_stock_net = 0
	ledger_changed.emit()


# ==================== 查询接口（供 UI 用）====================

# 生涯统计按大类排序（GainorLoss 用）：cur 过滤货币；income=true 只看收入、false 只看支出；
# ascending 控制升 / 降序。返回 [{"cat":int, "amount":int(绝对值)}]，跳过为 0 的来源。
func get_lifetime_sorted(cur: int, income: bool, ascending: bool) -> Array:
	var out := []
	for cat in CAT_META:
		var meta: Dictionary = CAT_META[cat]
		if meta["cur"] != cur or meta["income"] != income:
			continue
		if bool(meta.get("hidden", false)):
			continue
		var amt := int(lifetime.get(cat, 0))
		if amt == 0:
			continue
		out.append({"cat": cat, "amount": absi(amt)})
	if ascending:
		out.sort_custom(func(a, b): return a["amount"] < b["amount"])
	else:
		out.sort_custom(func(a, b): return a["amount"] > b["amount"])
	return out

# 时间流水（ListItems 用），含进行中的当天，最新在前。cat_filter=-1 表示该货币的全部来源。
# 返回 [{"day":int, "cat":int, "amount":int(有符号), "current":bool}]
func get_feed(cur: int, cat_filter: int = -1) -> Array:
	var out := []
	_append_day_rows(out, _cur_day, _cur_cats, cur, cat_filter, true)
	for i in range(daily_summary.size() - 1, -1, -1):
		var d: Dictionary = daily_summary[i]
		_append_day_rows(out, int(d["day"]), d["cats"], cur, cat_filter, false)
	return out

func _append_day_rows(out: Array, day: int, cats: Dictionary, cur: int, cat_filter: int, current: bool) -> void:
	for cat in cats:
		if cat_filter != -1 and cat != cat_filter:
			continue
		if int(CAT_META.get(cat, {}).get("cur", -1)) != cur:
			continue
		var amt := int(cats[cat])
		if amt == 0:
			continue
		out.append({"day": day, "cat": cat, "amount": amt, "current": current})

# 某天的员工级明细（含进行中当天）；超过 DETAIL_DAYS 天点不开，返回 []
func get_day_employees(day: int) -> Array:
	if day == _cur_day:
		return _emp_dict_to_array(_cur_emp)
	for d in daily_detail:
		if int(d["day"]) == day:
			return _emp_dict_to_array(d["emp"])
	return []

func can_expand_day(day: int) -> bool:
	if day == _cur_day:
		return true
	for d in daily_detail:
		if int(d["day"]) == day:
			return true
	return false

func _emp_dict_to_array(emp: Dictionary) -> Array:
	var out := []
	for uid in emp:
		var r: Dictionary = emp[uid]
		out.append({
			"uid": int(uid), "name": str(r.get("name", "")),
			"kpi": int(r.get("kpi", 0)), "dollar": int(r.get("dollar", 0)), "files": int(r.get("files", 0))
		})
	return out

# —— 员工进账窗口查询 ——
# “总计”模式：该货币下每员工生涯累计，按金额从多到少
func get_emp_totals(cur: int) -> Array:
	var key := "kpi" if cur == Cur.KPI else "dollar"
	var out := []
	for uid in lifetime_emp:
		var r: Dictionary = lifetime_emp[uid]
		var amt := int(r.get(key, 0))
		if amt == 0:
			continue
		out.append({"uid": int(uid), "name": str(r.get("name", "")), "amount": amt})
	out.sort_custom(func(a, b): return a["amount"] > b["amount"])
	return out

# “实时/按次”模式：该货币下最近的进账事件，最新在前，最多 limit 条
func get_recent_emp_events(cur: int, limit: int = RECENT_EMP_EVENTS_CAP) -> Array:
	var out := []
	for i in range(recent_emp_events.size() - 1, -1, -1):
		var e: Dictionary = recent_emp_events[i]
		if int(e["cur"]) != cur:
			continue
		out.append({"uid": int(e["uid"]), "name": str(e["name"]), "amount": int(e["amount"])})
		if out.size() >= limit:
			break
	return out


# 来源大类的显示名：优先用本地化(CSV 里配了就用)，没配则回退到这份内置中文默认，绝不显示原始 key
const DEFAULT_LABELS := {
	Cat.WORK_OUTPUT: "员工产出", Cat.WORK_INTERRUPT: "打断补偿", Cat.DECOR_SELL: "变卖家具",
	Cat.STOCK_SELL: "卖出股票", Cat.HIRE_KPI: "招聘员工", Cat.DESK_UPGRADE: "工位升级",
	Cat.RANK_UPGRADE: "员工升级", Cat.BUILD_DECOR: "建造与装修", Cat.STOCK_BUY: "买入股票",
	Cat.WORK_BONUS: "员工产出", Cat.SLACK_REWARD: "摸鱼挽回损失", Cat.STOCK_DIVIDEND: "股票分红",
	Cat.HEADHUNT: "猎头招聘", Cat.OTHER: "其他",
}

func cat_label(cat: int) -> String:
	var key := str(CAT_META.get(cat, {}).get("key", "LEDGER_OTHER"))
	var t := tr(key)
	return t if t != key else str(DEFAULT_LABELS.get(cat, key))

func cat_is_income(cat: int) -> bool:
	return bool(CAT_META.get(cat, {}).get("income", true))

func cat_is_expandable(cat: int) -> bool:
	return bool(CAT_META.get(cat, {}).get("expandable", false))


# ==================== 存档 ====================
func to_dict() -> Dictionary:
	return {
		"cur_day": _cur_day,
		"lifetime": lifetime.duplicate(true),
		"cur_cats": _cur_cats.duplicate(true),
		"cur_emp": _cur_emp.duplicate(true),
		"cur_stock_net": _cur_stock_net,
		"daily_summary": daily_summary.duplicate(true),
		"daily_detail": daily_detail.duplicate(true),
		"lifetime_emp": lifetime_emp.duplicate(true),
		"recent_emp_events": recent_emp_events.duplicate(true),
	}

func from_dict(d: Dictionary) -> void:
	_cur_day = int(d.get("cur_day", 0))
	lifetime = _int_key_dict(d.get("lifetime", {}))
	_cur_cats = _int_key_dict(d.get("cur_cats", {}))
	_cur_emp = _restore_emp(d.get("cur_emp", {}))
	_cur_stock_net = int(d.get("cur_stock_net", 0))
	daily_summary = _restore_summary(d.get("daily_summary", []))
	daily_detail = _restore_detail(d.get("daily_detail", []))
	lifetime_emp = _restore_lifetime_emp(d.get("lifetime_emp", {}))
	recent_emp_events = _restore_events(d.get("recent_emp_events", []))

func reset() -> void:
	_cur_day = 0
	lifetime = {}
	_cur_cats = {}
	_cur_emp = {}
	_cur_stock_net = 0
	daily_summary = []
	daily_detail = []
	lifetime_emp = {}
	recent_emp_events = []

# —— 读档辅助：JSON 会把整数字典键变成字符串，这里统一转回 int（对二进制存档也安全）——
func _int_key_dict(src) -> Dictionary:
	var out := {}
	if src is Dictionary:
		for k in src:
			out[int(k)] = int(src[k])
	return out

func _restore_emp(src) -> Dictionary:
	var out := {}
	if src is Dictionary:
		for k in src:
			var r = src[k]
			out[int(k)] = {
				"name": str(r.get("name", "")), "kpi": int(r.get("kpi", 0)),
				"dollar": int(r.get("dollar", 0)), "files": int(r.get("files", 0))
			}
	return out

func _restore_lifetime_emp(src) -> Dictionary:
	var out := {}
	if src is Dictionary:
		for k in src:
			var r = src[k]
			out[int(k)] = {"name": str(r.get("name", "")), "kpi": int(r.get("kpi", 0)), "dollar": int(r.get("dollar", 0))}
	return out

func _restore_events(src) -> Array:
	var out := []
	if src is Array:
		for e in src:
			out.append({"uid": int(e.get("uid", 0)), "name": str(e.get("name", "")), "cur": int(e.get("cur", 0)), "amount": int(e.get("amount", 0))})
	return out

func _restore_summary(src) -> Array:
	var out := []
	if src is Array:
		for e in src:
			out.append({"day": int(e.get("day", 0)), "cats": _int_key_dict(e.get("cats", {}))})
	return out

func _restore_detail(src) -> Array:
	var out := []
	if src is Array:
		for e in src:
			out.append({
				"day": int(e.get("day", 0)),
				"emp": _restore_emp(e.get("emp", {})),
				"stock_net": int(e.get("stock_net", 0))
			})
	return out
