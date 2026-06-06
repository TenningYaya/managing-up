# -*- coding: utf-8 -*-
"""
Managing Up —— 数值平衡模拟器
================================================

这个脚本严格按照游戏 GDScript 代码里的公式来模拟，方便在动手改代码前
先在 Excel/控制台里看清楚“调一个数会连带影响什么”。

所有常量都抄自实际代码（文件路径标在注释里），改这里就等于预览改游戏。

用法：
    python tools/balance_sim.py

输出三块：
    [A] 单员工产能表    —— 不同属性/Buff 下，每个员工每分钟产出多少 KPI、多久出一份文件
    [B] 阶段产能对比    —— 早/中/后期典型阵容，整间公司每分钟赚多少 KPI、多少美金
    [C] 升级进度时间线  —— 从 M2 一路爬到 M5（含满级桌子）大概要肝多久

注意：带随机性的结果都跑了多次取平均（蒙特卡洛），跑一次和跑十次数字会有点抖动属正常。
"""

import random
import statistics
from dataclasses import dataclass, field

# =============================================================================
# 第一部分：游戏常量（与代码一一对应，改这里 = 预览改数值）
# =============================================================================

# ---- 生产公式 (employee.gd) ----
BASE_KPI = 30                 # base_kpi_value，一份文件的基础 KPI
BASE_PROD_TIME = 600.0        # base_file_production_time，基础生产时间(秒)
BASE_REDUCTION = 30           # base_reduction_time，效率减幅基数
CYCLE_MULT = 0.5             # 生产时间最终乘数 (raw_duration * 0.5)
MIN_CYCLE = 1.0             # 保底最短周期(秒)
RANDOM_FACTOR_LO, RANDOM_FACTOR_HI = 0.8, 1.2   # 生产时间随机因子
KPI_SETTLE_MULT = 0.75       # 结算时 final_kpi = round(BASE_KPI * grade_mult * 0.75)

# ---- 文件质量评级 (employee.gd _finish_and_generate_file) ----
# 评分 = uniform(1,100) * (1 + 质量*2/100)，再按阈值评级
GRADES = [
    # (分数下限, 名称,   KPI倍率, 美金奖励)
    (95.0, "Gold",  2.0, 3),
    (71.0, "Blue",  1.5, 2),
    (31.0, "Green", 1.2, 1),
    (0.0,  "Gray",  1.0, 1),
]

# ---- Buff 强度 ----
SNACK_BUFF = 3               # 零食加成(随机加在 效率/质量/经验 之一)
SNACK_CHANCE = 0.5           # 每个生产周期尝试获得零食的概率
DESK_EFF_BUFF = 2            # 桌子 Lv2+ 效率 +2 (seat.gd)
DESK_QUAL_BUFF = 2           # 桌子 Lv3+ 质量 +2 (seat.gd)
CULTURE_BUFF = 2            # 文化中心每种 +2 (culture_center_logic.gd)
MEET_EFF = -1               # 会议室效率 -1 (employee.gd enter_meeting)
MEET_QUAL_LO, MEET_QUAL_HI = 1, 3   # 会议室质量 +1~3
MEET_EXP_LO,  MEET_EXP_HI  = 1, 3   # 会议室经验 +1~3

# ---- 摸鱼 (employee.gd) ----
SLACK_CHANCE = 0.02          # 出一份文件后 2% 概率摸鱼(会议中不摸鱼)

# ---- 属性上限 / 稀有度 (employee.gd _generate_attributes) ----
STAT_CAP = 10                # 单项属性上限
RARITY_SUM = {               # 三项属性总和的随机范围
    "R":   (3, 12),
    "SR":  (13, 21),
    "SSR": (22, 30),
}

# ---- 经济：升级成本 ----
PLAYER_UPGRADE_COST = {1: 50, 2: 1000, 3: 5000, 4: 15000}   # M1->M2 ... M4->M5 (upgrades_page.gd)
DESK_UPGRADE_COST = {1: 200, 2: 500, 3: 1000}               # 整排桌子 Lv1->2->3->4 (desk_upgrade_panel.gd)
HIRE_COST_PER_POINT = 50     # 招聘成本 = (eff+qual+exp)*50 (recruitment_manager.gd)
HEADHUNT_DOLLAR_PER = 100    # 猎头花费 = 100 美金/人 (recruitment_panel.gd)

# ---- 工位布局 ----
SEATS_PER_ROW = 6            # 每排 6 个座位 (DeskSlot.tscn 里 6 个 DeskSet)
MAX_ROWS = 5                # M5 解锁 5 排
# 解锁排数 = 玩家等级；桌子最高等级 = min(玩家等级, 4)

# ---- 免费简历到来节奏 (recruitment_manager.gd) ----
FREE_RECRUIT_EARLY = 120.0   # 前 3 个
FREE_RECRUIT_MID   = 600.0   # 第 4~10 个
FREE_RECRUIT_LATE  = 900.0   # 之后
FREE_SR_CHANCE = 0.10        # 免费简历 10% 出 SR，其余 R


# =============================================================================
# 第二部分：核心模型
# =============================================================================

@dataclass
class Buffs:
    """一间公司层面的环境 Buff（所有员工共享）"""
    desk_level: int = 1          # 该员工所在桌子的等级 1~4
    culture_eff: bool = False    # 文化中心：效率流
    culture_qual: bool = False   # 文化中心：质量流
    culture_exp: bool = False    # 文化中心：经验流
    pantry_slots: int = 0        # 茶水间提供的零食名额(全公司共享)
    in_meeting: bool = False     # 是否在会议室


@dataclass
class Employee:
    eff: int
    qual: int
    exp: int
    name: str = ""
    # 运行时状态
    snack: str = "NONE"          # NONE / EFF / QUAL / EXP
    work_elapsed: float = 0.0
    cycle_duration: float = 0.0
    slack_timer: float = 0.0     # >0 表示正在摸鱼倒计时

    @property
    def stat_sum(self) -> int:
        return self.eff + self.qual + self.exp


def gen_employee(rarity: str, rng: random.Random) -> Employee:
    """复刻 _generate_attributes：从 1/1/1 起，把剩余点随机洒在三项上(各自封顶10)"""
    lo, hi = RARITY_SUM[rarity]
    target = rng.randint(lo, hi)
    eff = qual = exp = 1
    remaining = target - 3
    # 防死循环：当三项都满 10 时停下
    guard = 0
    while remaining > 0 and guard < 1000:
        guard += 1
        pick = rng.randint(0, 2)
        if pick == 0 and eff < STAT_CAP:
            eff += 1; remaining -= 1
        elif pick == 1 and qual < STAT_CAP:
            qual += 1; remaining -= 1
        elif pick == 2 and exp < STAT_CAP:
            exp += 1; remaining -= 1
    return Employee(eff, qual, exp, name=rarity)


def final_eff(emp: Employee, b: Buffs) -> int:
    total = emp.eff
    if b.desk_level >= 2:
        total += DESK_EFF_BUFF
    if b.culture_eff:
        total += CULTURE_BUFF
    if emp.snack == "EFF":
        total += SNACK_BUFF
    if b.in_meeting:
        total += MEET_EFF
    return max(1, total)


def final_qual(emp: Employee, b: Buffs, rng: random.Random) -> int:
    total = emp.qual
    if b.desk_level >= 3:
        total += DESK_QUAL_BUFF
    if b.culture_qual:
        total += CULTURE_BUFF
    if emp.snack == "QUAL":
        total += SNACK_BUFF
    if b.in_meeting:
        total += rng.randint(MEET_QUAL_LO, MEET_QUAL_HI)
    return total


def start_cycle(emp: Employee, b: Buffs, rng: random.Random, snack_pool: list):
    """开始一个新生产周期：尝试拿零食、计算本轮时长"""
    # 尝试零食 (50% 且 有空名额)
    if emp.snack == "NONE" and snack_pool[0] < b.pantry_slots:
        if rng.random() <= SNACK_CHANCE:
            snack_pool[0] += 1
            emp.snack = rng.choice(["EFF", "QUAL", "EXP"])
    eff = final_eff(emp, b)
    rf = rng.uniform(RANDOM_FACTOR_LO, RANDOM_FACTOR_HI)
    raw = BASE_PROD_TIME - (eff * BASE_REDUCTION * rf)
    emp.cycle_duration = max(MIN_CYCLE, raw * CYCLE_MULT)
    emp.work_elapsed = 0.0


def finish_file(emp: Employee, b: Buffs, rng: random.Random, snack_pool: list):
    """复刻 _finish_and_generate_file，返回 (kpi, dollar, grade)"""
    init = rng.uniform(1.0, 100.0)
    q = final_qual(emp, b, rng)
    score = init * (1.0 + (q * 2.0) / 100.0)
    for lo, name, mult, dollar in GRADES:
        if score >= lo:
            grade, kpi_mult, dollar_reward = name, mult, dollar
            break
    kpi = round(BASE_KPI * kpi_mult * KPI_SETTLE_MULT)
    # 美金概率用「基础经验」(代码就是这么写的，不含 buff)
    dollar = 0
    dollar_chance = (1.0 + 0.5 * emp.exp) / 100.0
    if rng.random() <= dollar_chance:
        dollar = dollar_reward
    # 还掉零食名额
    if emp.snack != "NONE":
        snack_pool[0] -= 1
        emp.snack = "NONE"
    return kpi, int(dollar), grade


# =============================================================================
# 第三部分：稳态产能模拟（Mode A / B 的引擎）
# =============================================================================

def simulate(employees, buffs_of, pantry_slots, duration_s, rng,
             dt=1.0, slack_resolve_s=3.0, allow_slack=True):
    """
    跑一段时间，统计全公司产出。
    - employees: Employee 列表
    - buffs_of:  函数 emp -> Buffs（每个员工的环境）
    - pantry_slots: 全公司零食名额
    - slack_resolve_s: 摸鱼平均多久被玩家点掉（活跃玩家小、挂机大）
    返回 dict: total_kpi, total_dollar, files, grade_counts
    """
    snack_pool = [0]   # 用 list 当可变共享计数器
    total_kpi = 0
    total_dollar = 0
    files = 0
    grades = {g[1]: 0 for g in GRADES}

    # 初始化第一轮
    for emp in employees:
        emp.snack = "NONE"
        emp.slack_timer = 0.0
        start_cycle(emp, buffs_of(emp), rng, snack_pool)

    t = 0.0
    while t < duration_s:
        for emp in employees:
            b = buffs_of(emp)
            if emp.slack_timer > 0:
                emp.slack_timer -= dt
                if emp.slack_timer <= 0:
                    start_cycle(emp, b, rng, snack_pool)
                continue
            emp.work_elapsed += dt
            if emp.work_elapsed >= emp.cycle_duration:
                kpi, dollar, grade = finish_file(emp, b, rng, snack_pool)
                total_kpi += kpi
                total_dollar += dollar
                files += 1
                grades[grade] += 1
                # 摸鱼判定（会议中不摸鱼）
                if allow_slack and not b.in_meeting and rng.random() <= SLACK_CHANCE:
                    emp.slack_timer = slack_resolve_s
                else:
                    start_cycle(emp, b, rng, snack_pool)
        t += dt

    return {
        "kpi": total_kpi,
        "dollar": total_dollar,
        "files": files,
        "grades": grades,
        "minutes": duration_s / 60.0,
    }


def monte_carlo(run_fn, trials=8):
    """对一个返回 dict 的模拟函数跑多次取平均"""
    results = [run_fn(i) for i in range(trials)]
    avg = {}
    for key in ("kpi", "dollar", "files"):
        avg[key] = statistics.mean(r[key] for r in results)
    avg["minutes"] = results[0]["minutes"]
    # 评级合并
    grades = {g[1]: 0 for g in GRADES}
    for r in results:
        for k, v in r["grades"].items():
            grades[k] += v
    total = sum(grades.values()) or 1
    avg["grade_pct"] = {k: 100.0 * v / total for k, v in grades.items()}
    return avg


# =============================================================================
# 第四部分：报告 [A] 单员工产能表
# =============================================================================

def report_single_employee():
    print("\n" + "=" * 70)
    print("[A] 单员工产能表 —— 一个员工每分钟产出多少 KPI")
    print("=" * 70)
    print("（跑 1 小时 ×8 次取平均，零食/桌子/文化按列开关）\n")

    rng = random.Random(42)
    # 测试若干典型档位
    cases = [
        # (描述, eff, qual, exp, desk_level, culture, pantry)
        ("R 萌新(总6) 裸装",        2, 2, 2, 1, False, 0),
        ("R 满级(总12) 裸装",       4, 4, 4, 1, False, 0),
        ("SR(总17) 裸装",          6, 6, 5, 1, False, 0),
        ("SSR(总26) 裸装",         9, 9, 8, 1, False, 0),
        ("SSR 坐满级桌(Lv4)",      9, 9, 8, 4, False, 0),
        ("SSR 桌Lv4+双文化",       9, 9, 8, 4, True,  0),
        ("SSR 全堆满(桌+文化+零食)", 9, 9, 8, 4, True,  3),
    ]

    header = f"{'阵容':<26}{'KPI/分':>8}{'文件/分':>9}{'平均周期':>9}{'Gold%':>8}"
    print(header)
    print("-" * len(header))
    for desc, e, q, x, desk, culture, pantry in cases:
        emp = Employee(e, q, x)
        b = Buffs(desk_level=desk, culture_eff=culture, culture_qual=culture,
                  culture_exp=culture, pantry_slots=pantry)

        def run(seed):
            r = random.Random(1000 + seed)
            fresh = Employee(e, q, x)
            return simulate([fresh], lambda _e: b, pantry, 3600, r)

        avg = monte_carlo(run, trials=8)
        kpi_min = avg["kpi"] / avg["minutes"]
        files_min = avg["files"] / avg["minutes"]
        cycle = 60.0 / files_min if files_min > 0 else 0
        gold = avg["grade_pct"]["Gold"]
        print(f"{desc:<26}{kpi_min:>8.1f}{files_min:>9.2f}{cycle:>8.1f}s{gold:>7.1f}%")


# =============================================================================
# 第五部分：报告 [B] 阶段产能对比
# =============================================================================

def make_team(rarities, rng):
    return [gen_employee(r, rng) for r in rarities]


def report_stage_economy():
    print("\n" + "=" * 70)
    print("[B] 阶段产能对比 —— 整间公司每分钟赚多少")
    print("=" * 70)
    print("（每阶段随机生成阵容，跑 1 小时 ×8 次取平均）\n")

    # (阶段, 玩家等级, 阵容稀有度, 桌子等级, 文化, 茶水间名额)
    stages = [
        ("M2 早期", 2, ["R", "R", "R", "R"],                    1, False, 1),
        ("M3 中期", 3, ["R", "R", "SR", "SR", "R", "SR"],        2, False, 1),
        ("M4 中后", 4, ["SR"] * 8 + ["SSR"] * 2,                 3, False, 2),
        ("M5 后期", 5, ["SR"] * 10 + ["SSR"] * 6,               4, True,  3),
    ]

    header = (f"{'阶段':<10}{'人数':>5}{'KPI/分':>9}{'美金/分':>9}"
              f"{'KPI/时':>10}{'美金/时':>9}")
    print(header)
    print("-" * len(header))
    for name, lvl, rarities, desk, culture, pantry in stages:
        def run(seed):
            r = random.Random(7000 + seed)
            team = make_team(rarities, r)
            b = Buffs(desk_level=desk, culture_eff=culture, culture_qual=culture,
                      culture_exp=culture, pantry_slots=pantry)
            return simulate(team, lambda _e: b, pantry, 3600, r)

        avg = monte_carlo(run, trials=8)
        kpi_min = avg["kpi"] / avg["minutes"]
        dol_min = avg["dollar"] / avg["minutes"]
        print(f"{name:<10}{len(rarities):>5}{kpi_min:>9.1f}{dol_min:>9.2f}"
              f"{kpi_min*60:>10.0f}{dol_min*60:>9.1f}")

    print("\n参考成本：升级 M2->M3=1,000 / M3->M4=5,000 / M4->M5=15,000 KPI")
    print("         整排桌子 Lv1->4 总计 1,700 KPI；猎头 1 人=100 美金")


# =============================================================================
# 第六部分：报告 [C] 升级进度时间线
# =============================================================================

def report_progression():
    print("\n" + "=" * 70)
    print("[C] 升级进度时间线 —— 从 M2 肝到 M5 + 满级桌子要多久")
    print("=" * 70)
    print("策略：KPI 优先升玩家等级(解锁新排)，其次招人填座，再把已坐的桌子升到上限。")
    print("（贪心策略只是“一种合理玩法”，换个肝法时间会变；跑 ×6 次取平均）\n")

    def run_once(seed):
        rng = random.Random(20000 + seed)
        kpi = 0.0
        player_level = 2          # 教程结束默认 M2
        # 初始 3 个教程员工
        team = [gen_employee("R", rng) for _ in range(3)]
        seat_levels = {0: 1, 1: 1}   # 已解锁排的桌子等级 (M2=2排)
        # 简历池
        pool = []
        free_count = 0
        free_timer = FREE_RECRUIT_EARLY
        pantry = 1

        milestones = {}
        t = 0.0
        dt = 5.0
        snack_pool = [0]
        cap_minutes = 600   # 安全上限 10 小时

        # 给员工初始化周期
        def buffs_for(idx):
            lvl = seat_levels.get(idx, 1)
            culture = player_level >= 5
            return Buffs(desk_level=lvl, culture_eff=culture, culture_qual=culture,
                         culture_exp=culture, pantry_slots=pantry, in_meeting=False)

        # 座位 -> 员工 的占用（按解锁排顺序铺座位）
        # 简化：把 team 当作已就座，索引 // SEATS_PER_ROW = 第几排
        for emp in team:
            emp.snack = "NONE"
        # 初始化周期
        for i, emp in enumerate(team):
            start_cycle(emp, buffs_for(i // SEATS_PER_ROW), rng, snack_pool)

        while t < cap_minutes * 60:
            unlocked_rows = player_level
            seat_cap = unlocked_rows * SEATS_PER_ROW
            max_desk = min(player_level, 4)

            # --- 免费简历 ---
            free_timer -= dt
            if free_timer <= 0:
                rar = "SR" if rng.random() <= FREE_SR_CHANCE else "R"
                pool.append(gen_employee(rar, rng))
                free_count += 1
                free_timer = (FREE_RECRUIT_EARLY if free_count < 3
                              else FREE_RECRUIT_MID if free_count < 10
                              else FREE_RECRUIT_LATE)

            # --- 生产 ---
            for i, emp in enumerate(team):
                b = buffs_for(i // SEATS_PER_ROW)
                emp.work_elapsed += dt
                if emp.work_elapsed >= emp.cycle_duration:
                    k, _d, _g = finish_file(emp, b, rng, snack_pool)
                    kpi += k
                    start_cycle(emp, b, rng, snack_pool)

            # --- 贪心花钱 ---
            changed = True
            while changed:
                changed = False
                # 1) 升玩家等级
                if player_level < 5:
                    cost = PLAYER_UPGRADE_COST[player_level]
                    if kpi >= cost:
                        kpi -= cost
                        player_level += 1
                        milestones[player_level] = t / 60.0
                        # 新解锁一排，桌子默认 Lv1
                        seat_levels[player_level - 1] = 1
                        pantry = max(pantry, 1)
                        changed = True
                        continue
                # 2) 招人填空座（按最便宜的先招）
                if len(team) < seat_cap and pool:
                    pool.sort(key=lambda e: e.stat_sum)
                    cand = pool[0]
                    cost = cand.stat_sum * HIRE_COST_PER_POINT
                    if kpi >= cost:
                        kpi -= cost
                        pool.pop(0)
                        cand.snack = "NONE"
                        team.append(cand)
                        start_cycle(cand, buffs_for((len(team) - 1) // SEATS_PER_ROW), rng, snack_pool)
                        changed = True
                        continue
                # 3) 升桌子（已坐人的排，便宜的先升）
                best_row = None
                best_cost = None
                occupied_rows = (len(team) + SEATS_PER_ROW - 1) // SEATS_PER_ROW
                for row in range(occupied_rows):
                    lvl = seat_levels.get(row, 1)
                    if lvl < max_desk:
                        c = DESK_UPGRADE_COST[lvl]
                        if best_cost is None or c < best_cost:
                            best_cost, best_row = c, row
                if best_row is not None and kpi >= best_cost:
                    kpi -= best_cost
                    seat_levels[best_row] += 1
                    changed = True
                    continue

            # --- 完成判定：M5 且所有已解锁排 Lv4 ---
            if player_level >= 5:
                rows_full = all(seat_levels.get(r, 1) >= 4 for r in range(MAX_ROWS))
                if rows_full and len(team) >= MAX_ROWS * SEATS_PER_ROW * 0:  # 不强制坐满
                    pass
                if rows_full:
                    milestones["DONE"] = t / 60.0
                    break

            t += dt

        milestones.setdefault("DONE", t / 60.0)
        return milestones

    trials = 6
    runs = [run_once(i) for i in range(trials)]

    def avg_ms(key):
        vals = [r[key] for r in runs if key in r]
        return statistics.mean(vals) if vals else float("nan")

    print(f"{'里程碑':<22}{'平均用时(分钟)':>16}")
    print("-" * 40)
    labels = [(3, "到达 M3"), (4, "到达 M4"), (5, "到达 M5"), ("DONE", "M5 + 全桌满级")]
    prev = 0.0
    for key, label in labels:
        m = avg_ms(key)
        delta = m - prev if m == m else float("nan")
        print(f"{label:<22}{m:>12.1f}  (+{delta:.1f})")
        if m == m:
            prev = m
    print("\n注：教程(M1->M2)视为已完成，从 M2 + 3 名教程员工起算。")
    print("    招聘扣 KPI，会和升级抢钱，这是进度的主要瓶颈之一。")


# =============================================================================
# 主入口
# =============================================================================

if __name__ == "__main__":
    print("\n" + "#" * 70)
    print("#  Managing Up 数值平衡模拟器")
    print("#  所有公式来自游戏代码，改 balance_sim.py 顶部常量即可预览改数值效果")
    print("#" * 70)
    report_single_employee()
    report_stage_economy()
    report_progression()
    print("\n完成。想试 'M4->M5 改成 8000' 之类，改顶部常量再跑一次即可。\n")
