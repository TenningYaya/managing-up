# Managing Up —— 数值平衡模拟器 (GDScript 版)
# =============================================================================
# 用 Godot headless 直接跑，不依赖游戏场景/autoload，纯按代码里的公式算。
#
# 运行（PowerShell）：
#   & "D:\App_Install\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" `
#       --headless --path D:\6410_Github\managing-up --script res://tools/balance_sim.gd
#
# 输出三块：
#   [A] 单员工产能表    —— 不同属性/Buff 下每个员工每分钟产出多少 KPI
#   [B] 阶段产能对比    —— 早/中/后期整间公司每分钟赚多少 KPI / 美金
#   [C] 升级进度时间线  —— 从 M2 爬到 M5(含满桌)大概要肝多久
#
# 改顶部常量 = 预览“调这个数会怎样”，不用动游戏代码。
# =============================================================================
extends SceneTree

# 收集所有输出，最后既 print 到控制台、也写到 tools/sim_report.txt（兜底）
var _out: Array[String] = []
func p(s: String) -> void:
	_out.append(s)

# 进度模拟用的「可调成本」（tune 程序会改这几个，平时等于游戏默认值）
var cfg_player := {2: 1000, 3: 5000, 4: 15000}   # 玩家升级 KPI
var cfg_desk_mult := 1.0                          # 桌子成本倍率
var cfg_hire_mult := 1.0                          # 招聘成本倍率
var cfg_free_early := 120.0                       # 免费简历间隔：前3个
var cfg_free_mid := 600.0                         # 第4~10个
var cfg_free_late := 900.0                        # 之后

# ---- 生产公式 (employee.gd) ----
const BASE_KPI := 30
const BASE_PROD_TIME := 600.0
const BASE_REDUCTION := 30
const CYCLE_MULT := 0.5
const MIN_CYCLE := 1.0
const RF_LO := 0.8
const RF_HI := 1.2
const KPI_SETTLE_MULT := 0.75

# ---- 文件质量评级 (employee.gd) ----  [分数下限, 名称, KPI倍率, 美金]
const GRADES := [
	[95.0, "Gold", 2.0, 3],
	[71.0, "Blue", 1.5, 2],
	[31.0, "Green", 1.2, 1],
	[0.0, "Gray", 1.0, 1],
]

# ---- Buff 强度 ----
const SNACK_BUFF := 3
const SNACK_CHANCE := 0.5
const DESK_EFF_BUFF := 2     # 桌 Lv2+
const DESK_QUAL_BUFF := 2    # 桌 Lv3+
const CULTURE_BUFF := 2
const MEET_EFF := -1

# ---- 摸鱼 ----
const SLACK_CHANCE := 0.02
const SLACK_RESOLVE_S := 3.0   # 摸鱼平均多久被点掉(活跃玩家小/挂机大)

# ---- 属性/稀有度 (employee.gd) ----
const STAT_CAP := 10
const RARITY_SUM := {"R": [3, 12], "SR": [13, 21], "SSR": [22, 30]}

# ---- 经济：升级成本 ----
const PLAYER_UPGRADE_COST := {1: 50, 2: 1000, 3: 5000, 4: 15000}
const DESK_UPGRADE_COST := {1: 200, 2: 500, 3: 1000}
const HIRE_COST_PER_POINT := 50
const HEADHUNT_DOLLAR_PER := 100

# ---- 工位布局 ----
const SEATS_PER_ROW := 6     # DeskSlot.tscn 每排 6 个 DeskSet
const MAX_ROWS := 5

# ---- 免费简历节奏 (recruitment_manager.gd) ----
const FREE_EARLY := 120.0
const FREE_MID := 600.0
const FREE_LATE := 900.0
const FREE_SR_CHANCE := 0.10


# 一个员工（用 Dictionary 表示，省事）
func new_emp(e: int, q: int, x: int) -> Dictionary:
	return {"eff": e, "qual": q, "exp": x, "snack": "NONE",
		"elapsed": 0.0, "cycle": 0.0, "slack": 0.0, "row": 0}

# 环境 Buff
func new_buffs(desk := 1, culture := false, pantry := 0, meeting := false) -> Dictionary:
	return {"desk": desk, "culture": culture, "pantry": pantry, "meeting": meeting}


func gen_emp(rarity: String, rng: RandomNumberGenerator) -> Dictionary:
	var rng_range = RARITY_SUM[rarity]
	var target := rng.randi_range(rng_range[0], rng_range[1])
	var e := 1; var q := 1; var x := 1
	var remaining := target - 3
	var guard := 0
	while remaining > 0 and guard < 1000:
		guard += 1
		var pick := rng.randi_range(0, 2)
		if pick == 0 and e < STAT_CAP:
			e += 1; remaining -= 1
		elif pick == 1 and q < STAT_CAP:
			q += 1; remaining -= 1
		elif pick == 2 and x < STAT_CAP:
			x += 1; remaining -= 1
	return new_emp(e, q, x)


func final_eff(emp: Dictionary, b: Dictionary) -> int:
	var t: int = emp["eff"]
	if b["desk"] >= 2: t += DESK_EFF_BUFF
	if b["culture"]: t += CULTURE_BUFF
	if emp["snack"] == "EFF": t += SNACK_BUFF
	if b["meeting"]: t += MEET_EFF
	return maxi(1, t)


func final_qual(emp: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> int:
	var t: int = emp["qual"]
	if b["desk"] >= 3: t += DESK_QUAL_BUFF
	if b["culture"]: t += CULTURE_BUFF
	if emp["snack"] == "QUAL": t += SNACK_BUFF
	if b["meeting"]: t += rng.randi_range(1, 3)
	return t


func start_cycle(emp: Dictionary, b: Dictionary, rng: RandomNumberGenerator, snack_pool: Array) -> void:
	if emp["snack"] == "NONE" and snack_pool[0] < b["pantry"]:
		if rng.randf() <= SNACK_CHANCE:
			snack_pool[0] += 1
			emp["snack"] = ["EFF", "QUAL", "EXP"][rng.randi_range(0, 2)]
	var eff := final_eff(emp, b)
	var rf := rng.randf_range(RF_LO, RF_HI)
	var raw := BASE_PROD_TIME - (eff * BASE_REDUCTION * rf)
	emp["cycle"] = maxf(MIN_CYCLE, raw * CYCLE_MULT)
	emp["elapsed"] = 0.0


# 返回 [kpi, dollar, grade]
func finish_file(emp: Dictionary, b: Dictionary, rng: RandomNumberGenerator, snack_pool: Array) -> Array:
	var init_score := rng.randf_range(1.0, 100.0)
	var q := final_qual(emp, b, rng)
	var score := init_score * (1.0 + (q * 2.0) / 100.0)
	var grade := "Gray"; var mult := 1.0; var dollar_reward := 1
	for g in GRADES:
		if score >= g[0]:
			grade = g[1]; mult = g[2]; dollar_reward = g[3]
			break
	var kpi := int(round(BASE_KPI * mult * KPI_SETTLE_MULT))
	var dollar := 0
	var chance: float = (1.0 + 0.5 * float(emp["exp"])) / 100.0   # 美金概率用基础经验(代码如此)
	if rng.randf() <= chance:
		dollar = dollar_reward
	if emp["snack"] != "NONE":
		snack_pool[0] -= 1
		emp["snack"] = "NONE"
	return [kpi, dollar, grade]


# 跑一段稳态生产，返回统计 Dictionary
func simulate(emps: Array, buffs: Dictionary, duration_s: float, rng: RandomNumberGenerator,
		allow_slack := true) -> Dictionary:
	var dt := 1.0
	var snack_pool := [0]
	var total_kpi := 0
	var total_dollar := 0
	var files := 0
	var grade_counts := {"Gold": 0, "Blue": 0, "Green": 0, "Gray": 0}

	for emp in emps:
		emp["snack"] = "NONE"; emp["slack"] = 0.0
		start_cycle(emp, buffs, rng, snack_pool)

	var t := 0.0
	while t < duration_s:
		for emp in emps:
			if emp["slack"] > 0:
				emp["slack"] -= dt
				if emp["slack"] <= 0:
					start_cycle(emp, buffs, rng, snack_pool)
				continue
			emp["elapsed"] += dt
			if emp["elapsed"] >= emp["cycle"]:
				var res := finish_file(emp, buffs, rng, snack_pool)
				total_kpi += res[0]
				total_dollar += res[1]
				files += 1
				grade_counts[res[2]] += 1
				if allow_slack and not buffs["meeting"] and rng.randf() <= SLACK_CHANCE:
					emp["slack"] = SLACK_RESOLVE_S
				else:
					start_cycle(emp, buffs, rng, snack_pool)
		t += dt

	return {"kpi": total_kpi, "dollar": total_dollar, "files": files,
		"grades": grade_counts, "minutes": duration_s / 60.0}


# =============================================================================
# [A] 单员工产能表
# =============================================================================
func report_single() -> void:
	p("\n" + "=".repeat(72))
	p("[A] 单员工产能表 —— 一个员工每分钟产出多少 KPI （1小时×8次平均）")
	p("=".repeat(72))
	# 描述, eff, qual, exp, desk, culture, pantry
	var cases := [
		["R 萌新(总6) 裸装", 2, 2, 2, 1, false, 0],
		["R 满级(总12) 裸装", 4, 4, 4, 1, false, 0],
		["SR(总17) 裸装", 6, 6, 5, 1, false, 0],
		["SSR(总26) 裸装", 9, 9, 8, 1, false, 0],
		["SSR 坐满级桌(Lv4)", 9, 9, 8, 4, false, 0],
		["SSR 桌Lv4+双文化", 9, 9, 8, 4, true, 0],
		["SSR 全堆满(桌+文化+零食)", 9, 9, 8, 4, true, 3],
	]
	p("%-28s%9s%9s%10s%8s" % ["阵容", "KPI/分", "文件/分", "平均周期", "Gold%"])
	p("-".repeat(72))
	for c in cases:
		var b := new_buffs(c[4], c[5], c[6])
		var sum_kpi := 0.0; var sum_files := 0.0; var sum_gold := 0.0
		var trials := 8
		for s in range(trials):
			var rng := RandomNumberGenerator.new()
			rng.seed = 1000 + s
			var emp := new_emp(c[1], c[2], c[3])
			var r := simulate([emp], b, 3600.0, rng)
			sum_kpi += r["kpi"]
			sum_files += r["files"]
			var total: int = 0
			for g in r["grades"].values(): total += g
			if total > 0: sum_gold += 100.0 * r["grades"]["Gold"] / total
		var kpi_min := sum_kpi / trials / 60.0
		var files_min := sum_files / trials / 60.0
		var cycle := 60.0 / files_min if files_min > 0 else 0.0
		p("%-28s%9.1f%9.2f%9.1fs%7.1f%%" % [c[0], kpi_min, files_min, cycle, sum_gold / trials])


# =============================================================================
# [B] 阶段产能对比
# =============================================================================
func report_stage() -> void:
	p("\n" + "=".repeat(72))
	p("[B] 阶段产能对比 —— 整间公司每分钟赚多少 （1小时×8次平均）")
	p("=".repeat(72))
	# 阶段, 阵容, 桌等级, 文化, 茶水间
	var stages := [
		["M2 早期", ["R", "R", "R", "R"], 1, false, 1],
		["M3 中期", ["R", "R", "SR", "SR", "R", "SR"], 2, false, 1],
		["M4 中后", ["SR", "SR", "SR", "SR", "SR", "SR", "SR", "SR", "SSR", "SSR"], 3, false, 2],
		["M5 后期", ["SR", "SR", "SR", "SR", "SR", "SR", "SR", "SR", "SR", "SR",
			"SSR", "SSR", "SSR", "SSR", "SSR", "SSR"], 4, true, 3],
	]
	p("%-10s%6s%10s%10s%11s%10s" % ["阶段", "人数", "KPI/分", "美金/分", "KPI/时", "美金/时"])
	p("-".repeat(72))
	for st in stages:
		var rarities: Array = st[1]
		var b := new_buffs(st[2], st[3], st[4])
		var sum_kpi := 0.0; var sum_dollar := 0.0
		var trials := 8
		for s in range(trials):
			var rng := RandomNumberGenerator.new()
			rng.seed = 7000 + s
			var team := []
			for rar in rarities:
				team.append(gen_emp(rar, rng))
			var r := simulate(team, b, 3600.0, rng)
			sum_kpi += r["kpi"]
			sum_dollar += r["dollar"]
		var kpi_min := sum_kpi / trials / 60.0
		var dol_min := sum_dollar / trials / 60.0
		p("%-10s%6d%10.1f%10.2f%11.0f%10.1f" % [st[0], rarities.size(),
			kpi_min, dol_min, kpi_min * 60, dol_min * 60])
	p("\n参考成本：M2->M3=1,000 / M3->M4=5,000 / M4->M5=15,000 KPI")
	p("         整排桌子 Lv1->4 共 1,700 KPI；猎头 1 人 = 100 美金")


# =============================================================================
# [C] 升级进度时间线
# =============================================================================
func report_progression() -> void:
	p("\n" + "=".repeat(72))
	p("[C] 升级进度时间线 —— 从 M2 肝到 M5+满桌要多久 （×6次平均）")
	p("=".repeat(72))
	p("策略：KPI 优先升等级->招人填座->升已坐的桌子。招聘扣KPI会和升级抢钱。")

	var trials := 6
	var acc := {3: [], 4: [], 5: [], "DONE": []}
	for s in range(trials):
		var ms := run_progression(20000 + s)
		for k in ms.keys():
			if acc.has(k): acc[k].append(ms[k])

	p("%-24s%16s" % ["里程碑", "平均用时(分钟)"])
	p("-".repeat(42))
	var labels := [[3, "到达 M3"], [4, "到达 M4"], [5, "到达 M5"], ["DONE", "M5 + 全桌满级"]]
	var prev := 0.0
	for lb in labels:
		var arr: Array = acc[lb[0]]
		if arr.is_empty():
			p("%-24s%14s" % [lb[1], "未达成"])
			continue
		var m := 0.0
		for v in arr: m += v
		m /= arr.size()
		p("%-24s%12.1f  (+%.1f)" % [lb[1], m, m - prev])
		prev = m
	p("\n注：教程(M1->M2)视为已完成，从 M2 + 3 名教程员工起算。")


func run_progression(seed_val: int, stop_level := 99) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var kpi := 0.0
	var player_level := 2
	var team := []
	for i in range(3):
		team.append(gen_emp("R", rng))
	var seat_levels := {0: 1, 1: 1}   # M2 = 2 排
	var pool := []
	var free_count := 0
	var free_timer := cfg_free_early
	var pantry := 1
	var snack_pool := [0]
	var milestones := {}
	var t := 0.0
	var dt := 5.0
	var cap := 1500 * 60   # 25 小时安全上限（扫描时不卡顶）

	for i in range(team.size()):
		team[i]["row"] = i / SEATS_PER_ROW
		start_cycle(team[i], _buffs_for(team[i]["row"], seat_levels, player_level, pantry), rng, snack_pool)

	while t < cap:
		var seat_cap := player_level * SEATS_PER_ROW
		var max_desk: int = mini(player_level, 4)

		# 免费简历
		free_timer -= dt
		if free_timer <= 0:
			var rar := "SR" if rng.randf() <= FREE_SR_CHANCE else "R"
			pool.append(gen_emp(rar, rng))
			free_count += 1
			free_timer = cfg_free_early if free_count < 3 else (cfg_free_mid if free_count < 10 else cfg_free_late)

		# 生产
		for emp in team:
			var b := _buffs_for(emp["row"], seat_levels, player_level, pantry)
			emp["elapsed"] += dt
			if emp["elapsed"] >= emp["cycle"]:
				var res := finish_file(emp, b, rng, snack_pool)
				kpi += res[0]
				start_cycle(emp, b, rng, snack_pool)

		# 贪心花钱
		var changed := true
		while changed:
			changed = false
			# 1) 升等级
			if player_level < 5 and kpi >= cfg_player[player_level]:
				kpi -= cfg_player[player_level]
				player_level += 1
				milestones[player_level] = t / 60.0
				seat_levels[player_level - 1] = 1
				changed = true
				continue
			# 2) 招人填座
			if team.size() < seat_cap and not pool.is_empty():
				pool.sort_custom(func(a, c): return _stat_sum(a) < _stat_sum(c))
				var cand: Dictionary = pool[0]
				var cost := int(_stat_sum(cand) * HIRE_COST_PER_POINT * cfg_hire_mult)
				if kpi >= cost:
					kpi -= cost
					pool.pop_front()
					cand["snack"] = "NONE"
					cand["row"] = team.size() / SEATS_PER_ROW
					team.append(cand)
					start_cycle(cand, _buffs_for(cand["row"], seat_levels, player_level, pantry), rng, snack_pool)
					changed = true
					continue
			# 3) 升桌子
			var best_row := -1
			var best_cost := 0
			var occupied_rows: int = (team.size() + SEATS_PER_ROW - 1) / SEATS_PER_ROW
			for row in range(occupied_rows):
				var lvl: int = seat_levels.get(row, 1)
				if lvl < max_desk:
					var cst: int = int(DESK_UPGRADE_COST[lvl] * cfg_desk_mult)
					if best_row == -1 or cst < best_cost:
						best_cost = cst; best_row = row
			if best_row != -1 and kpi >= best_cost:
				kpi -= best_cost
				seat_levels[best_row] += 1
				changed = true
				continue

		# 提前停（用于逐级反解，省时间）
		if player_level >= stop_level:
			break

		# 完成判定
		if player_level >= 5:
			var full := true
			for r in range(MAX_ROWS):
				if seat_levels.get(r, 1) < 4:
					full = false; break
			if full:
				milestones["DONE"] = t / 60.0
				break
		t += dt

	if not milestones.has("DONE"):
		milestones["DONE"] = t / 60.0
	return milestones


func _buffs_for(row: int, seat_levels: Dictionary, player_level: int, pantry: int) -> Dictionary:
	var lvl: int = seat_levels.get(row, 1)
	var culture := player_level >= 5
	return new_buffs(lvl, culture, pantry, false)


func _stat_sum(emp: Dictionary) -> int:
	return emp["eff"] + emp["qual"] + emp["exp"]


# 用当前 cfg 跑 N 次进度模拟，返回各里程碑平均分钟
func avg_progression(trials: int, stop_level := 99) -> Dictionary:
	var acc := {3: 0.0, 4: 0.0, 5: 0.0, "DONE": 0.0}
	var cnt := {3: 0, 4: 0, 5: 0, "DONE": 0}
	for s in range(trials):
		var ms := run_progression(30000 + s, stop_level)
		for k in acc.keys():
			if ms.has(k):
				acc[k] += ms[k]; cnt[k] += 1
	var out := {}
	for k in acc.keys():
		out[k] = (acc[k] / cnt[k]) if cnt[k] > 0 else NAN
	return out


# 二分搜索：调某一级的升级成本，使「到达 milestone_key 级」的累计时间逼近 target_min
func solve_tier(tier: int, milestone_key, target_min: float, lo: float, hi: float,
		iters := 9, trials := 4) -> int:
	for i in range(iters):
		var mid := (lo + hi) / 2.0
		cfg_player[tier] = int(mid)
		var a := avg_progression(trials, milestone_key)   # 到该级就停，省时
		var t: float = a[milestone_key]
		if t < target_min:
			lo = mid
		else:
			hi = mid
	cfg_player[tier] = int((lo + hi) / 2.0)
	return cfg_player[tier]


# 反解一条「指数增长」的时间曲线
func solve_exponential(total_min: float, ratio: float) -> void:
	p("\n" + "=".repeat(78))
	p("[E] 反解指数时间曲线 —— 总时长≈%.0f分(%.1fh)，每级用时×%.1f递增" % [total_min, total_min / 60.0, ratio])
	p("=".repeat(78))
	# t1*(1+r+r^2)=total
	var t1 := total_min / (1.0 + ratio + ratio * ratio)
	var t2 := t1 * ratio
	var t3 := t1 * ratio * ratio
	var cum_m3 := t1
	var cum_m4 := t1 + t2
	var cum_m5 := t1 + t2 + t3
	p("目标每级用时：M2→M3 %.0f分 | M3→M4 %.0f分 | M4→M5 %.0f分" % [t1, t2, t3])
	p("目标累计时间：到M3 %.0f | 到M4 %.0f | 到M5 %.0f 分" % [cum_m3, cum_m4, cum_m5])
	p("（逐级二分搜索中…）")

	cfg_player = {2: 1000, 3: 5000, 4: 15000}
	var c2 := solve_tier(2, 3, cum_m3, 200, 6000)
	var c3 := solve_tier(3, 4, cum_m4, 2000, 60000)
	var c4 := solve_tier(4, 5, cum_m5, 8000, 250000)

	# 最终用完整 6 次验证
	cfg_player = {2: c2, 3: c3, 4: c4}
	var a := avg_progression(6)
	p("\n>>> 反解结果（建议成本）：")
	p("    M2→M3 = %d   (现 1000)" % c2)
	p("    M3→M4 = %d   (现 5000)" % c3)
	p("    M4→M5 = %d   (现 15000)" % c4)
	p(">>> 实测：到M3 %.0f分 | 到M4 %.0f分(+%.0f) | 到M5 %.0f分(+%.0f)" %
		[a[3], a[4], a[4] - a[3], a[5], a[5] - a[4]])
	p(">>> M2→M5 合计 %.1f 小时" % (a[5] / 60.0))
	cfg_player = {2: 1000, 3: 5000, 4: 15000}


# =============================================================================
# [D] 成本扫描：反推命中目标时长所需的玩家升级成本
# =============================================================================
func tune_scan(title: String, mults: Array, band_lo: float, band_hi: float) -> void:
	p("\n" + "=".repeat(78))
	p("[D] 成本扫描 —— %s" % title)
	p("=".repeat(78))
	p("做法：玩家升级成本整体按倍率缩放（桌子/招聘成本不动），看总时长怎么变")
	p("目标带：到 M5 落在 %.0f~%.0f 分钟" % [band_lo, band_hi])
	p("%-7s%-22s%9s%9s%9s%11s" % ["倍率", "M3/M4/M5成本", "到M3", "到M4", "到M5", "到M5(小时)"])
	p("-".repeat(78))
	var base := {2: 1000, 3: 5000, 4: 15000}
	for mult in mults:
		cfg_player = {2: int(base[2] * mult), 3: int(base[3] * mult), 4: int(base[4] * mult)}
		var a := avg_progression(5)
		var cost_str := "%d/%d/%d" % [cfg_player[2], cfg_player[3], cfg_player[4]]
		var hit := "  <== 命中" if a[5] >= band_lo and a[5] <= band_hi else ""
		p("%-7s%-22s%9.0f%9.0f%9.0f%11.1f%s" % ["%.2fx" % mult, cost_str, a[3], a[4], a[5], a[5] / 60.0, hit])
	cfg_player = base.duplicate()


# 测试一组「自定义」组合配置，打印每级耗时（用于精调）
# recruit_mult：免费简历间隔倍率，<1 = 招募更快
func tune_custom(label: String, player: Dictionary, desk_mult := 1.0, hire_mult := 1.0, recruit_mult := 1.0) -> void:
	cfg_player = player.duplicate()
	cfg_desk_mult = desk_mult
	cfg_hire_mult = hire_mult
	cfg_free_early = 120.0 * recruit_mult
	cfg_free_mid = 600.0 * recruit_mult
	cfg_free_late = 900.0 * recruit_mult
	var a := avg_progression(6)
	p("\n方案【%s】" % label)
	p("  升级 M2->M3=%d / M3->M4=%d / M4->M5=%d ｜ 桌×%.2f ｜ 招聘×%.2f ｜ 招募间隔×%.2f"
		% [player[2], player[3], player[4], desk_mult, hire_mult, recruit_mult])
	p("  简历节奏：前3个每%.0f分 / 第4~10每%.0f分 / 之后每%.0f分"
		% [cfg_free_early / 60.0, cfg_free_mid / 60.0, cfg_free_late / 60.0])
	p("  到M3 %.0f分 | 到M4 %.0f分(+%.0f) | 到M5 %.0f分(+%.0f) | 满桌 %.0f分"
		% [a[3], a[4], a[4] - a[3], a[5], a[5] - a[4], a["DONE"]])
	var band := "  ✅ 命中 2~3 小时" if a[5] >= 120 and a[5] <= 180 else "  （目标 120~180 分）"
	p("  ==> M2→M5 合计 %.1f 小时%s" % [a[5] / 60.0, band])
	# 还原默认
	cfg_player = {2: 1000, 3: 5000, 4: 15000}
	cfg_desk_mult = 1.0
	cfg_hire_mult = 1.0
	cfg_free_early = 120.0; cfg_free_mid = 600.0; cfg_free_late = 900.0


# =============================================================================
# SceneTree 命令行入口：对象构造时调用 _init()
func _init() -> void:
	p("\n" + "#".repeat(72))
	p("#  Managing Up 数值平衡模拟器 (GDScript / 公式同步自游戏代码)")
	p("#  改 tools/balance_sim.gd 顶部常量即可预览“调这个数会怎样”")
	p("#".repeat(72))
	# 本轮：反解「M2→M5≈10 小时、每级用时指数(×2)递增」的升级成本
	solve_exponential(600.0, 2.0)
	p("\n完成。\n")

	# 输出：打印到控制台 + 写入 tools/sim_report.txt（兜底，便于查看）
	var text := "\n".join(_out)
	print(text)
	var f := FileAccess.open("res://tools/sim_report.txt", FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
	quit()
