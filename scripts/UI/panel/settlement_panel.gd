# settlement_panel.gd
# 培训结算弹窗：培训结束（自然跑完或手动结束）且有收获时居中弹出。
# VBoxContainer 里按"有收益的员工"逐条叠 TrainingSettlementBar：
#   头像 | 名字 | 属性icon | EFF+2 | 迷你属性条(白色闪烁段=本次收获)
# 零收获不弹。点面板外部任意处关闭。
extends Control

const BAR_SCENE := preload("res://scenes/UI/custom/training_settlement_bar.tscn")

const ATTR_ICONS := {
	"eff": preload("res://assets/office/training/modified-eff-training-2.png"),
	"qual": preload("res://assets/office/training/qual-training.png"),
	"exp": preload("res://assets/office/training/exp-training.png"),
}
const ATTR_COLORS := {
	"eff": Color("4fb2ff"),
	"qual": Color("eeb422"),
	"exp": Color("76c442"),
}
const ATTR_ABBR := {
	"eff": "Sidebar_TRAIN_ABBR_EFF",
	"qual": "Sidebar_TRAIN_ABBR_QUAL",
	"exp": "Sidebar_TRAIN_ABBR_EXP",
}

# 名字栏最大宽度：名字太长自动缩小字号塞进这个宽度（同 resume 名字的"量宽自适应"思路）
const NAME_MAX_WIDTH := 100.0
const NAME_MIN_FONT := 10   # 字号下限，再长也别缩成蚂蚁

# 头像裁剪（同培训面板那套，只是框缩到 40px，focus 等比缩小）
const AVATAR_SIZE := 40.0
const HEAD_ZOOM := 2.0
const HEAD_FOCUS_R := 11.5
const HEAD_FOCUS_HIGH := 13.0

@onready var _vbox: VBoxContainer = $VBoxContainer

func _ready() -> void:
	add_to_group("training_settlement_panel")
	hide()
	# 确认按钮（"共同进步！"）与关闭按钮都关面板；面板外点击【不】关闭——这窗是成果报告，别被误触划走
	var ok_btn = find_child("NormalButton", true, false)
	if ok_btn:
		ok_btn.button_text = "Sidebar_TRAINING_SETTLE_OK"   # NormalButton 自带 tr() 且随语言自动刷新
		ok_btn.pressed.connect(hide)
	var close_btn = find_child("ClosePanel", true, false)
	if close_btn and close_btn.has_signal("pressed"):
		close_btn.pressed.connect(hide)

# results: [{ "emp": Employee, "key": "eff"/"qual"/"exp", "gain": int }]
# 由 TrainingRoomLogic 在培训结束时调用；空列表不弹。
func show_results(results: Array) -> void:
	if results.is_empty():
		return
	# 只清结果条（按"是不是 training_settlement_bar 场景的实例"判断，条的根节点类型随你改）；按钮等其它控件保留
	for c in _vbox.get_children():
		if c.scene_file_path == BAR_SCENE.resource_path:
			c.queue_free()   # 场景里摆的预览条 / 上次的结果都清掉
	var built := 0
	for r in results:
		var emp = r.get("emp")
		if not is_instance_valid(emp):
			continue   # 培训期间被开除的就不上榜了
		_vbox.add_child(_build_bar(emp, str(r.get("key", "eff")), int(r.get("gain", 0))))
		built += 1
	if built == 0:
		return
	# 确认按钮永远压在最后一行（新条是 add_child 追加的，会跑到按钮后面，挪回来）
	var ok_btn = find_child("NormalButton", true, false)
	if ok_btn and ok_btn.get_parent() == _vbox:
		_vbox.move_child(ok_btn, _vbox.get_child_count() - 1)
	# 居中弹出
	var vp := get_viewport().get_visible_rect().size
	position = ((vp - size) / 2.0).floor()
	show()
	move_to_front()

func _build_bar(emp, key: String, gain: int) -> Control:
	var bar := BAR_SCENE.instantiate()
	# 条内控件都按【名字】递归查找（find_child），所以你在场景里随便套容器/挪层级都不用改代码

	# ---- 头像：清掉占位图，塞裁到头部的立绘 ----
	var slot: Control = bar.find_child("Avatar", true, false)
	if slot != null:
		if slot is TextureRect:
			slot.texture = null
		_build_avatar_into(slot, emp)

	# ---- 名字（只要名不要姓：名字库本就只存名，这里再防一手带空格的自定义名/保底名）----
	var name_lbl: Label = bar.find_child("NameLabel", true, false)
	if name_lbl:
		var full: String = emp.get_display_name() if emp.has_method("get_display_name") else str(emp.employee_name)
		name_lbl.text = _given_name(full)
		_fit_name_font(name_lbl, NAME_MAX_WIDTH)

	# ---- 属性 icon + 结果文字（缩写走本地化：中文"效率+2"，英文"EFF+2"）----
	var icon: TextureRect = bar.find_child("AttributeIcon", true, false)
	if icon and ATTR_ICONS.has(key):
		icon.texture = ATTR_ICONS[key]
	var result_lbl: Label = bar.find_child("ResultLabel", true, false)
	if result_lbl:
		result_lbl.text = "%s+%d" % [tr(ATTR_ABBR.get(key, "")), gain]
		result_lbl.add_theme_color_override("font_color", ATTR_COLORS.get(key, Color.WHITE))

	# ---- 迷你属性条（你在条场景里摆的 TrainingMiniBar，节点名 MiniBar；没摆也不报错）----
	var mini = bar.find_child("MiniBar", true, false)
	if mini and mini.has_method("setup"):
		var total := 0
		var trained := 0
		match key:
			"eff":
				total = emp.efficiency
				trained = emp.trained_eff
			"qual":
				total = emp.quality
				trained = emp.trained_qual
			"exp":
				total = emp.experience
				trained = emp.trained_exp
		# session 段 = 本次培训的收获 → 结算里白色闪烁的正是"这次练出来的"
		mini.setup(ATTR_COLORS.get(key, Color.WHITE), total, trained, gain)

	return bar

# 名字自适应：量出文字实际宽度，超过 max_w 就按比例缩小字号（复用 resume 名字的测宽思路；
# 用缩字号而非 scale 压扁，是因为 Label 的最小宽度会把整行撑宽，缩字号则布局天然 ≤ max_w）
func _fit_name_font(lbl: Label, max_w: float) -> void:
	var font := lbl.get_theme_font("font")
	var fsize := lbl.get_theme_font_size("font_size")
	if font == null or fsize <= 0 or max_w <= 0.0:
		return
	var text_w := font.get_string_size(lbl.text, lbl.horizontal_alignment, -1, fsize).x
	if text_w > max_w:
		var new_size := maxi(NAME_MIN_FONT, int(floor(fsize * max_w / text_w)))
		lbl.add_theme_font_size_override("font_size", new_size)

# 只要"名"：带空格的（英文自定义名/保底名 "Angela Baby"）取第一段；中文名字库本就无姓，原样返回
func _given_name(full: String) -> String:
	var s := full.strip_edges()
	var sp := s.find(" ")
	if sp > 0:
		return s.substr(0, sp)
	return s

# 在槽位控件内居中放一个 40px 的头像（裁到头部+面部，同培训面板）
func _build_avatar_into(slot: Control, emp) -> void:
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 锚定槽位中心，四向各撑 AVATAR_SIZE/2 —— 不依赖布局完成时机
	clip.anchor_left = 0.5
	clip.anchor_top = 0.5
	clip.anchor_right = 0.5
	clip.anchor_bottom = 0.5
	clip.offset_left = -AVATAR_SIZE / 2.0
	clip.offset_top = -AVATAR_SIZE / 2.0
	clip.offset_right = AVATAR_SIZE / 2.0
	clip.offset_bottom = AVATAR_SIZE / 2.0
	slot.add_child(clip)

	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	var focus_y: float = HEAD_FOCUS_R if int(emp.rarity) == int(Employee.Rarity.R) else HEAD_FOCUS_HIGH
	holder.pivot_offset = Vector2(AVATAR_SIZE * 0.5, focus_y)
	holder.position = Vector2(0.0, AVATAR_SIZE * 0.5 - focus_y)
	holder.scale = Vector2(HEAD_ZOOM, HEAD_ZOOM)
	clip.add_child(holder)
	AvatarHelper.apply_portrait(holder, emp.portrait, emp.rarity)
