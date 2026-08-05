# ledger_panel.gd —— 会计报表面板
# 两个页签(KPI / 美金)，每页两个下拉共用一个 ScrollContainer：
#   · ListItems 下拉  → 选来源(含“全部”)，按时间列该来源流水
#   · GainorLoss 下拉 → 选排序(含“全部”)，列开局至今的排行
# 行样式：绿▲/红▼当 bullet(悬挂缩进)，来源蓝色(可展开的带下划线超链接)，赚绿赔红。
# 开局关闭；点 LedgerButton 开/关；点面板外部自动关。
extends Control

const GREEN_HEX := "2fae4e"   # 赚：绿
const RED_HEX := "d64a3b"     # 赔：红
const GREEN := Color(0.184, 0.682, 0.306)
const RED := Color(0.839, 0.290, 0.231)

# 行文字的字体与字号：选中场景里的 LedgerPanel 节点，右侧 Inspector 直接改这两项即可
@export var row_font: Font = preload("res://assets/fonts/standard.tres")
@export var row_font_size: int = 20
@export var source_color: Color = Color(0.36, 0.72, 1.0)   # 来源名颜色（浅蓝，易读；可在 Inspector 里调）

# 每天数据之间的虚线分割线：正中间留一块空位放 icon（day_divider_icon 不填就只留空、不画图）
@export var day_divider_icon: Texture2D = null
@export var day_divider_gap: float = 24.0                        # 中间留给 icon 的空隙宽度（像素）
@export var day_divider_color: Color = Color(0.5, 0.5, 0.5, 0.7)  # 虚线颜色

# 绿▲/红▼小箭头：用绘制的实心三角，避免像素字体缺 ▲▼ 字形显示成方块
class ArrowMark extends Control:
	var up := true
	var color := Color.WHITE
	func _ready() -> void:
		resized.connect(queue_redraw)
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var pts: PackedVector2Array
		if up:
			pts = PackedVector2Array([Vector2(w * 0.5, h * 0.15), Vector2(w * 0.9, h * 0.7), Vector2(w * 0.1, h * 0.7)])
		else:
			pts = PackedVector2Array([Vector2(w * 0.1, h * 0.3), Vector2(w * 0.9, h * 0.3), Vector2(w * 0.5, h * 0.85)])
		draw_colored_polygon(pts, color)

# 每天之间的虚线分割线：横向虚线，正中间空出 gap 宽度放 icon（有 icon 就画在正中）
class DashDivider extends Control:
	var icon: Texture2D = null
	var gap := 24.0          # 中间留白宽度
	var dash := 5.0          # 短划长度
	var space := 4.0         # 短划间距
	var thickness := 2.0
	var color := Color(0.5, 0.5, 0.5, 0.7)
	func _ready() -> void:
		resized.connect(queue_redraw)
	func _draw() -> void:
		var w := size.x
		var y := size.y * 0.5
		var cx := w * 0.5
		var half := gap * 0.5
		_dash_seg(0.0, cx - half, y)
		_dash_seg(cx + half, w, y)
		if icon:
			var isz: float = minf(gap, size.y)
			draw_texture_rect(icon, Rect2(cx - isz * 0.5, y - isz * 0.5, isz, isz), false)
	func _dash_seg(x0: float, x1: float, y: float) -> void:
		var x := x0
		while x < x1:
			var xe: float = minf(x + dash, x1)
			draw_line(Vector2(x, y), Vector2(xe, y), color, thickness)
			x += dash + space

var _tab_cfg := []          # [{idx, cur, list_ob, gain_ob, vbox, mode}]
var _ledger_button: Button = null
var _dirty := false
var _refresh_timer := 0.0


func _ready() -> void:
	hide()   # 开局关闭
	set_process_input(true)
	# 找到并绑定 LedgerButton（同为 CanvasLayer 的子节点）
	_ledger_button = get_parent().get_node_or_null("LedgerButton")
	if _ledger_button:
		_ledger_button.pressed.connect(_on_button_pressed)
	_setup_tabs()
	Ledger.ledger_changed.connect(_on_ledger_changed)
	$TabContainer.tab_changed.connect(func(_i): _refresh_active())


func _setup_tabs() -> void:
	_tab_cfg = [
		_make_cfg(0, Ledger.Cur.KPI, $TabContainer/KPI),
		_make_cfg(1, Ledger.Cur.DOLLAR, $TabContainer/Assets),
	]
	var tc: TabContainer = $TabContainer
	tc.set_tab_title(0, tr("LEDGER_TAB_KPI"))
	tc.set_tab_title(1, tr("LEDGER_TAB_ASSETS"))


func _make_cfg(idx: int, cur: int, tab_root: Control) -> Dictionary:
	var list_ob: OptionButton = tab_root.get_node("VBoxContainer/HBoxContainer/ListItems")
	var gain_ob: OptionButton = tab_root.get_node("VBoxContainer/HBoxContainer/GainorLoss")
	var scroll: ScrollContainer = tab_root.get_node("VBoxContainer/ScrollContainer")

	# 让下拉平分顶部一行，滚动区吃满剩余高度
	list_ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gain_ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED   # 关横向滚动，行文本才会自动换行

	# 在 ScrollContainer 里建一个 VBox 装所有行（消掉“ScrollContainer 需要子节点”的告警）
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)

	_apply_font(list_ob)
	_apply_font(gain_ob)

	# ListItems：全部 + 本货币的每个来源（隐藏项如“打断补偿”已并入产出，不单列）
	list_ob.clear()
	list_ob.add_item(tr("LEDGER_ALL"))
	list_ob.set_item_metadata(0, -1)
	var i := 1
	for cat in Ledger.CAT_META:
		if int(Ledger.CAT_META[cat]["cur"]) != cur:
			continue
		if bool(Ledger.CAT_META[cat].get("hidden", false)):
			continue
		list_ob.add_item(Ledger.cat_label(cat))
		list_ob.set_item_metadata(i, cat)
		i += 1

	# GainorLoss：全部 + 4 种排序
	gain_ob.clear()
	gain_ob.add_item(tr("LEDGER_ALL"))                # 0
	gain_ob.add_item(tr("LEDGER_SORT_INCOME_ASC"))    # 1
	gain_ob.add_item(tr("LEDGER_SORT_INCOME_DESC"))   # 2
	gain_ob.add_item(tr("LEDGER_SORT_EXPENSE_ASC"))   # 3
	gain_ob.add_item(tr("LEDGER_SORT_EXPENSE_DESC"))  # 4

	var cfg := {"idx": idx, "cur": cur, "list_ob": list_ob, "gain_ob": gain_ob, "vbox": vbox, "mode": "feed"}

	# 哪个下拉最后被动过，就用哪种模式渲染（两下拉共用同一 ScrollContainer）
	list_ob.item_selected.connect(func(_s): cfg["mode"] = "feed"; _rebuild(idx))
	gain_ob.item_selected.connect(func(_s): cfg["mode"] = "rank"; _rebuild(idx))
	return cfg


# ==================== 开 / 关 ====================
func _on_button_pressed() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	# 打开时提到最上层，保证输入命中优先
	var p := get_parent()
	if p:
		p.move_child(self, p.get_child_count() - 1)
	show()
	# 面板打开期间关闭员工交互总闸，防止点击穿透到底下地图上的员工（与事件弹窗同款做法）
	Gamemanager.is_employee_interaction_disabled = true
	_refresh_active()

func close() -> void:
	hide()
	# 延迟一帧再恢复：避免“点面板外关闭”的这同一次点击又落到员工身上
	Gamemanager.set_deferred("is_employee_interaction_disabled", false)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mp := get_global_mouse_position()
		if get_global_rect().has_point(mp):
			return   # 点在面板内 → 保持打开
		if _ledger_button and _ledger_button.get_global_rect().has_point(mp):
			return   # 点在按钮上 → 交给按钮 toggle，别在这里重复关
		close()      # 点其它任何地方 → 自动关闭


# ==================== 刷新 ====================
func _on_ledger_changed() -> void:
	if visible:
		_dirty = true   # 高频交易只置脏，_process 里节流重建

func _process(dt: float) -> void:
	if not visible or not _dirty:
		return
	_refresh_timer += dt
	if _refresh_timer >= 0.4:
		_refresh_timer = 0.0
		_dirty = false
		_refresh_active()

func _refresh_active() -> void:
	if not visible:
		return
	_rebuild($TabContainer.current_tab)


func _rebuild(idx: int) -> void:
	if idx < 0 or idx >= _tab_cfg.size():
		return
	var cfg: Dictionary = _tab_cfg[idx]
	var vbox: VBoxContainer = cfg["vbox"]
	for c in vbox.get_children():
		c.queue_free()

	var rows: Array = _build_rank(cfg) if cfg["mode"] == "rank" else _build_feed(cfg)
	if rows.is_empty():
		var empty := Label.new()
		empty.text = tr("LEDGER_EMPTY")
		empty.modulate = Color(1, 1, 1, 0.5)
		_apply_font(empty)
		vbox.add_child(empty)
		return
	# 逐行加入；进入新的一天前插一条虚线分割（排行模式 day 恒为 -1，不会触发分割）
	var prev_day := 0x7fffffff
	var first := true
	for r in rows:
		var day := int(r["day"])
		if not first and day != prev_day:
			vbox.add_child(_make_divider())
		vbox.add_child(_make_row(r))
		prev_day = day
		first = false


func _make_divider() -> Control:
	var d := DashDivider.new()
	d.icon = day_divider_icon
	d.gap = day_divider_gap
	d.color = day_divider_color
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d.custom_minimum_size = Vector2(0, maxf(day_divider_gap, 16.0))   # 高度容纳 icon 空位
	return d


# 时间流水：按 ListItems 选的来源(或全部)，最新在前
func _build_feed(cfg: Dictionary) -> Array:
	var list_ob: OptionButton = cfg["list_ob"]
	var cat_filter := -1
	var md = list_ob.get_selected_metadata()
	if md != null:
		cat_filter = int(md)
	var out := []
	for e in Ledger.get_feed(int(cfg["cur"]), cat_filter):
		var expandable: bool = Ledger.cat_is_expandable(int(e["cat"])) and Ledger.can_expand_day(int(e["day"]))
		out.append({
			"cat": int(e["cat"]), "amount": int(e["amount"]),
			"day": int(e["day"]), "current": bool(e["current"]),
			"expandable": expandable, "meta": "%d|%d" % [int(e["day"]), int(e["cat"])]
		})
	return out

# 生涯排行：按 GainorLoss 选的排序(或全部)
func _build_rank(cfg: Dictionary) -> Array:
	var cur := int(cfg["cur"])
	var sel: int = cfg["gain_ob"].selected
	var out := []
	if sel <= 0:
		# 全部：本货币所有来源，按绝对值从多到少
		for cat in Ledger.CAT_META:
			if int(Ledger.CAT_META[cat]["cur"]) != cur:
				continue
			if bool(Ledger.CAT_META[cat].get("hidden", false)):
				continue
			var amt := int(Ledger.lifetime.get(cat, 0))
			if amt == 0:
				continue
			out.append({"cat": cat, "amount": amt, "day": -1, "current": false, "expandable": false, "meta": ""})
		out.sort_custom(func(a, b): return absi(a["amount"]) > absi(b["amount"]))
	else:
		var income := sel == 1 or sel == 2
		var asc := sel == 1 or sel == 3
		for e in Ledger.get_lifetime_sorted(cur, income, asc):
			var signed := int(e["amount"]) if income else -int(e["amount"])
			out.append({"cat": int(e["cat"]), "amount": signed, "day": -1, "current": false, "expandable": false, "meta": ""})
	return out


# 把 Inspector 里设的字体/字号套到控件上（RichTextLabel 的主题项名和普通控件不同，分别处理）
func _apply_font(c: Control) -> void:
	if c is RichTextLabel:
		if row_font:
			c.add_theme_font_override("normal_font", row_font)
		c.add_theme_font_size_override("normal_font_size", row_font_size)
	else:
		if row_font:
			c.add_theme_font_override("font", row_font)
		c.add_theme_font_size_override("font_size", row_font_size)


# 造一行：绿▲/红▼ + 来源(蓝，可展开则加下划线超链接) + 金额(赚绿赔红)。换行从箭头之后开始(悬挂缩进)。
func _make_row(r: Dictionary) -> Control:
	var amount := int(r["amount"])
	var income := amount >= 0

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)

	var arrow := ArrowMark.new()
	arrow.up = income
	arrow.color = GREEN if income else RED
	arrow.custom_minimum_size = Vector2(maxf(10.0, row_font_size * 0.8), row_font_size + 2)   # 随字号缩放
	arrow.size_flags_vertical = Control.SIZE_SHRINK_BEGIN   # 顶对齐，像 bullet
	row.add_child(arrow)

	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_font(rt)
	rt.meta_clicked.connect(_on_meta_clicked)

	var blue_hex := source_color.to_html(false)
	var name := Ledger.cat_label(int(r["cat"]))
	var name_bb := ""
	if bool(r["expandable"]):
		name_bb = "[url=%s][color=#%s][u]%s[/u][/color][/url]" % [str(r["meta"]), blue_hex, name]
	else:
		name_bb = "[color=#%s]%s[/color]" % [blue_hex, name]

	var amt_txt := "+%d" % amount if income else "%d" % amount
	var amt_bb := "[color=#%s]%s[/color]" % [GREEN_HEX if income else RED_HEX, amt_txt]

	rt.text = "%s  %s" % [name_bb, amt_bb]
	row.add_child(rt)
	return row


# ==================== 超链接互动接口（预留）====================
# 点击“员工产出”这类可展开来源时触发。meta 形如 "day|cat"。
# 具体展开表现待定，这里先把接口和数据取好，方便你后续填。
func _on_meta_clicked(meta: Variant) -> void:
	var parts := str(meta).split("|")
	if parts.size() != 2:
		return
	var day := int(parts[0])
	var cat := int(parts[1])
	var employees := Ledger.get_day_employees(day)
	# TODO: 在此实现员工级明细的展开表现（弹层 / 内嵌子列表等）。
	print("[Ledger] 展开 day=%d cat=%d，当天员工明细：%s" % [day, cat, str(employees)])
