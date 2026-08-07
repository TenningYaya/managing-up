# daily_current.gd —— 员工进账实时窗口
# 由 LedgerPanel 的“员工产出”超链接打开，按货币(KPI/美金)分别统计。
#   · 默认“实时/按次”：每笔进账一条，最新在最下，新条目实时冒出并自动滚到底
#   · SelectionButton 切“总计”：每个员工累计多少，从多到少
#   · PinButon 图钉：固定后脱离 LedgerPanel 挂到顶层，Ledger 关了也可见，可整窗拖动
#   · CloseButton 关闭
extends Control

const BLUE_HEX := "6cb6ff"    # 浅蓝：配深色面板底比深蓝更易读
const GREEN_HEX := "2fae4e"
const GREEN := Color(0.184, 0.682, 0.306)

@export var row_font: Font = preload("res://assets/fonts/standard.tres")
@export var row_font_size: int = 18
@export var pin_texture_off: Texture2D = null   # 灰图钉（未固定）
@export var pin_texture_on: Texture2D = null    # 白图钉（已固定）

# 绿▲：员工进账都是收入，恒为向上绿三角
class ArrowMark extends Control:
	var color := Color.WHITE
	func _ready() -> void:
		resized.connect(queue_redraw)
	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, h * 0.15), Vector2(w * 0.9, h * 0.7), Vector2(w * 0.1, h * 0.7)]), color)

@onready var _sel_btn = $VBoxContainer/Selections/SelectionButton
@onready var _pin_btn = $VBoxContainer/Selections/PinButon          # 注意：场景里节点名是 PinButon（少个 t）
@onready var _pin_tex: TextureRect = $VBoxContainer/Selections/PinButon/PinTexture
@onready var _scroll: ScrollContainer = $VBoxContainer/CurrentLogContainer
@onready var _log: VBoxContainer = $VBoxContainer/CurrentLogContainer/CurrentLog
@onready var _close_btn: Button = $CloseButton
@onready var _bg: Control = $Background

var _cur: int = 0            # 当前统计货币（Ledger.Cur.KPI / DOLLAR）
var _mode := "live"          # "live"=实时按次；"total"=总计
var _pinned := false
var _home_parent: Node = null   # 未固定时的家（LedgerPanel）
var _dirty := false
var _refresh_timer := 0.0
var _dragging := false
var _drag_offset := Vector2.ZERO


func _ready() -> void:
	hide()
	add_to_group("sidebar_panel")   # 让地图上的员工不被“穿透点击”（employee.gd 会查这个组）
	_home_parent = get_parent()

	# 让容器空白处也能拖动：容器设 PASS，按钮/滚动区各自 STOP 照常工作
	$VBoxContainer.mouse_filter = Control.MOUSE_FILTER_PASS
	$VBoxContainer/Selections.mouse_filter = Control.MOUSE_FILTER_PASS
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED   # 关横向滚动，行文本才换行

	_bg.gui_input.connect(_on_bg_gui_input)
	_sel_btn.pressed.connect(_on_sel_pressed)
	_pin_btn.pressed.connect(_on_pin_pressed)
	_close_btn.pressed.connect(close)
	Ledger.ledger_changed.connect(_on_ledger_changed)

	_update_sel_label()
	_update_pin_visual()


# 供 LedgerPanel 调用：按货币打开窗口
func open_for(cur: int) -> void:
	_cur = cur
	show()
	var p := get_parent()
	if p:
		p.move_child(self, p.get_child_count() - 1)   # 提到最前
	_rebuild()


func close() -> void:
	hide()


# ==================== 模式切换 ====================
func _on_sel_pressed() -> void:
	_mode = "total" if _mode == "live" else "live"
	_update_sel_label()
	_rebuild()

func _update_sel_label() -> void:
	# 按钮上写的永远是“另一个模式”
	_sel_btn.button_text = "LEDGER_MODE_TOTAL" if _mode == "live" else "LEDGER_MODE_LIVE"


# ==================== 图钉：固定 / 取消固定 ====================
func _on_pin_pressed() -> void:
	_pinned = not _pinned
	if _pinned:
		# 脱离 LedgerPanel，挂到它上层的 CanvasLayer：独立于 Ledger 显隐、屏幕空间不随相机、置于最顶
		var top := _home_parent.get_parent()
		if top:
			reparent(top, true)
			top.move_child(self, top.get_child_count() - 1)
	else:
		# 收回 LedgerPanel 下（随 Ledger 显隐）
		reparent(_home_parent, true)
	_update_pin_visual()

func _update_pin_visual() -> void:
	if _pin_tex:
		var t: Texture2D = pin_texture_on if _pinned else pin_texture_off
		if t:
			_pin_tex.texture = t


# ==================== 刷新 ====================
func _on_ledger_changed() -> void:
	if visible:
		_dirty = true   # 每有员工进账就置脏，_process 里节流重建

func _process(dt: float) -> void:
	if not visible or not _dirty:
		return
	_refresh_timer += dt
	if _refresh_timer >= 0.3:
		_refresh_timer = 0.0
		_dirty = false
		_rebuild()

func _rebuild() -> void:
	for c in _log.get_children():
		c.queue_free()

	if _mode == "total":
		for e in Ledger.get_emp_totals(_cur):
			_log.add_child(_make_line(str(e["name"]), int(e["amount"])))
	else:
		# get_recent_emp_events 最新在前；要“最新在最下”，倒着加
		var evts: Array = Ledger.get_recent_emp_events(_cur)
		for i in range(evts.size() - 1, -1, -1):
			_log.add_child(_make_line(str(evts[i]["name"]), int(evts[i]["amount"])))
		_scroll_to_bottom_deferred()

func _scroll_to_bottom_deferred() -> void:
	await get_tree().process_frame
	var vb := _scroll.get_v_scroll_bar()
	if vb:
		_scroll.scroll_vertical = int(vb.max_value)


func _make_line(emp_name: String, amount: int) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)

	var arrow := ArrowMark.new()
	arrow.color = GREEN
	arrow.custom_minimum_size = Vector2(maxf(10.0, row_font_size * 0.8), row_font_size + 2)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(arrow)

	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if row_font:
		rt.add_theme_font_override("normal_font", row_font)
	rt.add_theme_font_size_override("normal_font_size", row_font_size)
	rt.text = "[color=#%s]%s[/color]  [color=#%s]+%d[/color]" % [BLUE_HEX, emp_name, GREEN_HEX, amount]
	row.add_child(rt)
	return row


# ==================== 整窗拖动（背景空白处即可拖）====================
func _on_bg_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_drag_offset = get_global_mouse_position() - global_position
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() - _drag_offset


# 供 employee.gd 判定“点在 UI 上、别穿透到地图员工”
func blocks_point(screen_pos: Vector2) -> bool:
	return visible and get_global_rect().has_point(screen_pos)
