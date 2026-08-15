# steam_manager.gd
# GodotSteam 封装单例：初始化 Steam + 每帧回调 + 解锁成就 + 累计进度持久化。
# autoload 名 SteamManager；游戏各处用 SteamManager.unlock(...) / register_xxx(...) 上报。
#
# 【重要】每个 ACH_* 常量右边的字符串,必须和 Steamworks 后台
#        (App Admin → Stats & Achievements) 里创建的成就 "API Name" 一字不差。
extends Node

## Managing Up 的正式 Steam App ID(不是 1741470,那是程序包 ID)。
const APP_ID: int = 5021770

## 玩家最高等级 = 6(M6),达到即解锁"传奇工贼"。
const MAX_PLAYER_LEVEL: int = 6

## 累计进度存这里(独立于游戏存档,跨存档/跨周目累积——Steam 成就本就是账号级永久的)。
const PROGRESS_PATH := "user://steam_achievements.json"

# 阈值
const KPI_TARGET := 10000
const DOLLAR_TARGET := 10000
const FISH_CLICK_TARGET := 20   # 禁止摸鱼:累计点掉摸鱼气泡次数
const EMP_CLICK_TARGET := 20    # 工作量不饱和:连续点同一员工次数

# ————————————— 成就 API Name(与后台一致) —————————————
const ACH_MAX_LEVEL        := "ACH_MAX_LEVEL"        # 传奇工贼：玩家等级达到最高
const ACH_KPI_10000        := "ACH_KPI_10000"        # 第一桶金：获取 10000 KPI
const ACH_DOLLAR_10000     := "ACH_DOLLAR_10000"     # 第一桶美金：获取 10000 美金
const ACH_DRAW_SSR         := "ACH_DRAW_SSR"         # SSR?!：抽到一个 SSR
const ACH_ALL_DESKS_FULL   := "ACH_ALL_DESKS_FULL"   # 座无虚席：座位全部坐满
const ACH_FISH_BUBBLE_20   := "ACH_FISH_BUBBLE_20"   # 禁止摸鱼：点击摸鱼气泡 20 次
const ACH_ALL_EVENTS       := "ACH_ALL_EVENTS"       # 全部事件：体验完全部随机事件
const ACH_FIRST_URGE       := "ACH_FIRST_URGE"       # 我做主：增加一次员工催促 message
const ACH_CLICK_EMP_20     := "ACH_CLICK_EMP_20"     # 工作量不饱和：连续点击同一员工 20 次(隐藏)
const ACH_PERFECT_EMPLOYEE := "ACH_PERFECT_EMPLOYEE" # 你是主还是我是主：抽到属性全满的员工

const ALL_ACHIEVEMENTS := [
	ACH_MAX_LEVEL, ACH_KPI_10000, ACH_DOLLAR_10000, ACH_DRAW_SSR,
	ACH_ALL_DESKS_FULL, ACH_FISH_BUBBLE_20, ACH_ALL_EVENTS,
	ACH_FIRST_URGE, ACH_CLICK_EMP_20, ACH_PERFECT_EMPLOYEE,
]

var enabled: bool = false            # Steam 是否成功初始化
var _stats_ready: bool = false       # 玩家成就/统计是否已从 Steam 拉回
var _pending: Array[String] = []     # 统计就绪前想解锁的,先排队
var _unlocked: Dictionary = {}       # 本地缓存已解锁 id,避免重复调用 Steam

# —— 累计/持久化进度 ——
var _seen_events: Dictionary = {}    # 用作集合:事件id -> true
var _fish_clicks: int = 0

# —— 运行时(不持久化)——
var _emp_streak_uid: int = -1        # 上次被点击的员工 uid
var _emp_streak: int = 0             # 连续点击同一员工的次数


func _ready() -> void:
	_load_progress()
	_init_steam()
	_wire_game_signals()


func _process(_delta: float) -> void:
	# init 时传了 embed_callbacks=false,所以要自己每帧跑回调(成就提示气泡靠它弹出)
	if enabled:
		Steam.run_callbacks()


# ————————————— 初始化 —————————————
func _init_steam() -> void:
	# 正式发行时可在这里加:若不是从 Steam 启动则重启走 Steam。开发期(有 steam_appid.txt)不要开。
	# if Steam.restartAppIfNecessary(APP_ID): get_tree().quit()

	enabled = Steam.steamInit(APP_ID, false)  # 返回 bool;false=回调自己每帧跑
	if not enabled:
		push_warning("[Steam] 初始化失败(多半是 Steam 客户端没开)。本次运行成就禁用,游戏照常运行。")
		return
	print("[Steam] 已连接,玩家: %s (AppID %d)" % [Steam.getPersonaName(), APP_ID])
	Steam.user_stats_received.connect(_on_user_stats_received)
	Steam.requestUserStats(Steam.getSteamID())  # 主动拉取当前玩家的成就/统计


func _on_user_stats_received(_game_id: int, _result: int, _user_id: int) -> void:
	if _stats_ready:
		return
	_stats_ready = true
	# 补发统计就绪前排队的解锁
	for id in _pending:
		_do_unlock(id)
	_pending.clear()
	# 累计型成就:若历史进度已达标(上次没能上报),补发一次
	if _fish_clicks >= FISH_CLICK_TARGET:
		unlock(ACH_FISH_BUBBLE_20)
	if _seen_events.size() >= _total_events():
		unlock(ACH_ALL_EVENTS)


# ————————————— 对外:解锁 —————————————
## 解锁成就。随时可调、重复调用无害;Steam 未开时自动忽略。
func unlock(achievement_id: String) -> void:
	if not enabled or _unlocked.has(achievement_id):
		return
	if not _stats_ready:
		if achievement_id not in _pending:
			_pending.append(achievement_id)
		return
	_do_unlock(achievement_id)


func _do_unlock(achievement_id: String) -> void:
	_unlocked[achievement_id] = true  # 先记本地,避免同一帧重复上报
	var info: Dictionary = Steam.getAchievement(achievement_id)
	if info.get("achieved", false):
		return  # Steam 上已经解锁过了,不重复
	Steam.setAchievement(achievement_id)
	Steam.storeStats()  # 关键:必须 store 才会真正上报并弹出提示气泡
	print("[Steam] 解锁成就: ", achievement_id)


## 进度型提示气泡(可选):例如让 Steam 弹"5/20"。达 max 不会自动解锁,仍需另外 unlock()。
func indicate_progress(achievement_id: String, current: int, maximum: int) -> void:
	if enabled and _stats_ready and not _unlocked.has(achievement_id):
		Steam.indicateAchievementProgress(achievement_id, current, maximum)


## 调试用:清空全部成就 + 累计进度(慎用,正式版别调)。
func debug_reset_all() -> void:
	_seen_events.clear()
	_fish_clicks = 0
	_save_progress()
	if not enabled:
		return
	for id in ALL_ACHIEVEMENTS:
		Steam.clearAchievement(id)
	Steam.storeStats()
	_unlocked.clear()
	print("[Steam] 已清空全部成就与进度")


# ————————————— 调试：键盘测试(仅 debug 版本有效，release 导出自动失效) —————————————
func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_F9:   # 打印全部成就当前状态(不弹窗也能确认是否已记录到 Steam)
			_debug_print_status()
		KEY_F10:  # 一键解锁全部成就(测上报/弹窗)
			for id in ALL_ACHIEVEMENTS:
				unlock(id)
		KEY_F11:  # 清空全部成就+进度,方便反复测
			debug_reset_all()


func _debug_print_status() -> void:
	if not enabled:
		print("[Steam] 未连接，无法查询成就状态")
		return
	print("——————— 成就状态 ———————")
	for id in ALL_ACHIEVEMENTS:
		var info: Dictionary = Steam.getAchievement(id)
		print("  %-22s %s" % [id, ("✔ 已解锁" if info.get("achieved", false) else "· 未解锁")])


# ————————————— 对外:游戏事件上报 —————————————
## 摸鱼气泡被玩家点掉一次(禁止摸鱼)
func register_fish_click() -> void:
	if _unlocked.has(ACH_FISH_BUBBLE_20):
		return
	_fish_clicks += 1
	_save_progress()
	if _fish_clicks >= FISH_CLICK_TARGET:
		unlock(ACH_FISH_BUBBLE_20)


## 体验过一个随机事件(全部事件)。event_id 用事件首条消息 key。
func mark_event_seen(event_id: String) -> void:
	if event_id == "" or _seen_events.has(event_id):
		return
	_seen_events[event_id] = true
	_save_progress()
	if _seen_events.size() >= _total_events():
		unlock(ACH_ALL_EVENTS)


## 玩家点击了某个员工一次(工作量不饱和:连续点同一员工)
func register_employee_click(employee_uid: int) -> void:
	if employee_uid == _emp_streak_uid:
		_emp_streak += 1
	else:
		_emp_streak_uid = employee_uid
		_emp_streak = 1
	if _emp_streak >= EMP_CLICK_TARGET:
		unlock(ACH_CLICK_EMP_20)


# ————————————— 与游戏信号对接 —————————————
func _wire_game_signals() -> void:
	Gamemanager.level_changed.connect(_on_level_changed)
	Gamemanager.kpi_changed.connect(_on_kpi_changed)
	Gamemanager.dollar_changed.connect(_on_dollar_changed)
	EmployeeManager.employee_map_status_changed.connect(_on_map_status_changed)


func _on_level_changed(new_level: int) -> void:
	if new_level >= MAX_PLAYER_LEVEL:
		unlock(ACH_MAX_LEVEL)  # 传奇工贼


func _on_kpi_changed(new_value: int) -> void:
	if new_value >= KPI_TARGET:
		unlock(ACH_KPI_10000)  # 第一桶金


func _on_dollar_changed(new_value: int) -> void:
	if new_value >= DOLLAR_TARGET:
		unlock(ACH_DOLLAR_10000)  # 第一桶美金


func _on_map_status_changed() -> void:
	if _unlocked.has(ACH_ALL_DESKS_FULL):
		return
	if _are_all_unlocked_desks_full():
		unlock(ACH_ALL_DESKS_FULL)  # 座无虚席


## 所有"已解锁"的工位座位是否都坐了人(且至少存在一个已解锁座位,防开局0座即达成)。
## 若想改成"必须全 30 座满",在末尾再加 Gamemanager.player_level >= 5 的判断即可。
func _are_all_unlocked_desks_full() -> bool:
	var seen_seat := false
	for slot in get_tree().get_nodes_in_group("desk_slots"):
		if slot.is_locked:            # 只看已解锁的桌组
			continue
		for seat in slot.grid_container.get_children():
			if seat is DeskSeat:
				seen_seat = true
				if seat.is_free():    # occupant == null
					return false
	return seen_seat


# ————————————— 持久化 —————————————
func _total_events() -> int:
	return EventDefinitions.EVENTS.size()


func _load_progress() -> void:
	if not FileAccess.file_exists(PROGRESS_PATH):
		return
	var f := FileAccess.open(PROGRESS_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return
	_fish_clicks = int(data.get("fish_clicks", 0))
	for k in data.get("seen_events", []):
		_seen_events[str(k)] = true


func _save_progress() -> void:
	var f := FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"fish_clicks": _fish_clicks,
		"seen_events": _seen_events.keys(),
	}))
	f.close()
