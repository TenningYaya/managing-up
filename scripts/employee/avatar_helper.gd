# avatar_helper.gd
class_name AvatarHelper
extends RefCounted

# ==========================================================
# 🎨 头像底图样式开关
#   true  = 稀有度纯色底（当前使用）
#   false = 回到原来的三张插图底（RARITY_BGS）
# 改这一个 bool 就能整体切换，两套资源都保留，随时可逆。
# ==========================================================
const USE_SOLID_COLOR_BG := true

# 方案 A：纯色底（想微调颜色改这里的色值即可）
const RARITY_COLORS = {
	Employee.Rarity.R:   Color("add692ff"),   # 淡米黄
	Employee.Rarity.SR:  Color("6ab9bdff"),   # 淡橙
	Employee.Rarity.SSR: Color("f5d349ff")    # 淡粉红
}

# 方案 B：原插图底（保留不删，把上面的开关改 false 就恢复）
const RARITY_BGS = {
	Employee.Rarity.R: preload("res://assets/UI/employee/raritybcg/r_bcg.png"),
	Employee.Rarity.SR: preload("res://assets/UI/employee/raritybcg/sr_bcg.png"),
	Employee.Rarity.SSR: preload("res://assets/UI/employee/raritybcg/ssr_bcg.png")
}

# ==========================================================
# 🧵 底纹开关：在纯色底上再叠一层硬边纹理（夹在底色与角色立绘之间）
#   R   = 坐标纸网格   SR = 45°斜纹   SSR = 放射线
# 想回到"干净纯色"就把这个改 false，不影响上面的配色。
# ==========================================================
const USE_BG_PATTERN := true

const BG_PATTERN_SHADER := preload("res://data/shader/avatar_bg_pattern.gdshader")

# 纹理色相对底色的深浅偏移：
#   正数 = 提亮（纹理发白）  负数 = 压暗（纹理变深）
# 0.35 提亮 / -0.22 压暗 是两个比较顺眼的起点。
const PATTERN_TINT := -0.22

# 每种稀有度的纹理参数（随便调，改完直接跑）
#   type: 1=网格 2=斜纹 3=放射   alpha: 强度   cell: 周期   line: 线宽
#   rays: 放射线条数（取偶数）   ray_rot: 整体旋转角度   ray_org: 放射中心（(0.5,0.5)=正中）
const RARITY_PATTERNS = {
	Employee.Rarity.R:   {"type": 1, "alpha": 0.5, "cell": 8.0, "line": 1.0},
	Employee.Rarity.SR:  {"type": 2, "alpha": 0.5, "cell": 9.0, "line": 2.0},
	Employee.Rarity.SSR: {"type": 3, "alpha": 0.3, "rays": 28.0, "ray_rot": 12.0, "ray_org": Vector2(0.5, 0.45)}
}

# 三种稀有度各一份材质，全项目共用（不是每个头像一份），内存开销可忽略
static var _bg_mats := {}

static func _get_bg_material(emp_rarity: Employee.Rarity) -> ShaderMaterial:
	if _bg_mats.has(emp_rarity):
		return _bg_mats[emp_rarity]

	var base: Color = RARITY_COLORS.get(emp_rarity, Color.WHITE)
	var p: Dictionary = RARITY_PATTERNS.get(emp_rarity, {})

	# 纹理色由底色本身派生（同色系才不发脏，比直接用黑/白自然得多）：
	#   PATTERN_TINT > 0 → 提亮（发白）   < 0 → 压暗
	var pat_col: Color = (
		base.lightened(PATTERN_TINT) if PATTERN_TINT >= 0.0 else base.darkened(-PATTERN_TINT)
	)

	var mat := ShaderMaterial.new()
	mat.shader = BG_PATTERN_SHADER
	mat.set_shader_parameter("base_color", base)
	mat.set_shader_parameter("pattern_color", pat_col)
	mat.set_shader_parameter("pattern_type", int(p.get("type", 0)))
	mat.set_shader_parameter("pattern_alpha", float(p.get("alpha", 0.15)))
	mat.set_shader_parameter("cell_size", float(p.get("cell", 8.0)))
	mat.set_shader_parameter("line_width", float(p.get("line", 1.0)))
	mat.set_shader_parameter("ray_count", float(p.get("rays", 14.0)))
	mat.set_shader_parameter("ray_rotation", float(p.get("ray_rot", 0.0)))
	mat.set_shader_parameter("ray_origin", p.get("ray_org", Vector2(0.5, 0.5)))

	_bg_mats[emp_rarity] = mat
	return mat

# ==========================================================
# 🖼 照片白边框（可选）：像一寸照的衬边，画在最顶层
# 只有传 show_frame=true 的调用点才会出现（员工面板），
# 仓库小卡片等地方默认不加，免得 75px 的卡子被边框吃掉太多空间。
# ==========================================================
# 🎨 边框配色表：每个稀有度单独填，随便调。
# 当前这三个值 = 各自底色的"变淡 55%"版本，只是给你一个起点，改成任何颜色都行。
const RARITY_FRAME_COLORS = {
	Employee.Rarity.R:   Color("f2eda2ff"),   # 对应底色 add692
	Employee.Rarity.SR:  Color("cecce3ff"),   # 对应底色 6ab9bd
	Employee.Rarity.SSR: Color("eff2b6ff")    # 对应底色 f5d349
}
const FRAME_WIDTH := 10                # 边框粗细（像素）
const FRAME_LAYER := "FrameLayer"

# 边框朝哪边长：
#   false = 向【内】长（当前）。白边往中间挤，吃掉的是背景的外圈留白，
#           更像一寸照的白色衬边。人物周围本来就有空白，挤十几二十像素没问题。
#   true  = 向【外】扩。照片区域不缩水，但边框会画到 Figure 矩形之外、可能蹭到旁边信息栏。
const FRAME_OUTWARD := false

# 三种稀有度各一份边框样式，全项目共用（和 _bg_mats 一个思路）
static var _frame_styles := {}

static func _get_frame_style(emp_rarity: Employee.Rarity) -> StyleBoxFlat:
	if _frame_styles.has(emp_rarity):
		return _frame_styles[emp_rarity]

	var sb := StyleBoxFlat.new()
	sb.draw_center = false            # 只画边框，中间透空，不遮住头像
	sb.border_color = RARITY_FRAME_COLORS.get(emp_rarity, Color.WHITE)
	sb.set_border_width_all(FRAME_WIDTH)
	sb.set_corner_radius_all(0)
	sb.anti_aliasing = false          # 像素风：硬边，不要抗锯齿的半透明过渡
	if FRAME_OUTWARD:
		# 把 StyleBox 的绘制范围整体外扩一圈，边框正好落在原矩形【之外】，
		# 于是照片区域完全不被侵占，粗细可以随便调。
		sb.set_expand_margin_all(FRAME_WIDTH)

	_frame_styles[emp_rarity] = sb
	return sb

static func _set_frame_layer(parent: Control, show_frame: bool, emp_rarity: Employee.Rarity) -> void:
	var layer: Panel = parent.get_node_or_null(FRAME_LAYER) as Panel
	if not show_frame:
		if layer:
			layer.hide()
		return
	if layer == null:
		layer = Panel.new()
		layer.name = FRAME_LAYER
		layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(layer)
	# ⚠️ 每次都重设样式，不能只在创建时设：
	#    员工面板的 Figure 节点是复用的，换看一个不同稀有度的员工时
	#    边框必须跟着换色，否则会残留上一个人的颜色。
	layer.add_theme_stylebox_override("panel", _get_frame_style(emp_rarity))
	layer.show()

# 纯色底用的 1×1 白色贴图：拉满整块后靠 modulate 染色。
# 这样底图层始终是同一个 TextureRect，两种方案切换不会出现节点类型冲突。
static var _white_tex: ImageTexture = null

static func _get_white_tex() -> ImageTexture:
	if _white_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex

static func apply_portrait(target_node: Control, portrait_tex: Texture2D, emp_rarity: Employee.Rarity = Employee.Rarity.R, show_frame: bool = false) -> void:
	if target_node == null: return
	
	# 1. 父节点自己不再拿图，清空它，防止它挡住子节点或被挡住
	if target_node is TextureRect: target_node.texture = null
	elif target_node is TextureButton: target_node.texture_normal = null
		
	if portrait_tex == null:
		_clear_layer(target_node, "BgLayer")
		_clear_layer(target_node, "BodyLayer")
		_clear_layer(target_node, "ClothesBottomLayer")
		_clear_layer(target_node, "ClothesTopLayer")
		_clear_layer(target_node, "AccGlassesLayer") # 🌟 清空眼镜
		_clear_layer(target_node, "HairLayer")
		_clear_layer(target_node, "AccHatLayer")     # 🌟 清空帽子
		return
		
	# 2. 按照“从底到顶”的顺序严格创建/刷新图层
	
	# 第一层：背景（纯色 / 插图 由 USE_SOLID_COLOR_BG 决定）
	_set_bg_layer(target_node, emp_rarity)
	
	# 第二层：人体 (Body)
	_set_body_layer(target_node, portrait_tex, "BodyLayer")
		
	# 第三层：下装
	_set_or_clear_layer(target_node, portrait_tex, "clothes_bottom_tex", "clothes_bottom_rect", "ClothesBottomLayer")
	
	# 第四层：上装
	_set_or_clear_layer(target_node, portrait_tex, "clothes_top_tex", "clothes_top_rect", "ClothesTopLayer")
	
	# 🌟 第五层：眼镜 (加在衣服和头发之间，防止刘海被眼镜反向遮挡)
	_set_or_clear_layer(target_node, portrait_tex, "acc_glasses_tex", "acc_glasses_rect", "AccGlassesLayer")
	
	# 第六层：头发
	_set_or_clear_layer(target_node, portrait_tex, "hair_tex", "hair_rect", "HairLayer")
	
	# 🌟 第七层：帽子 (绝对的顶点，必须盖在头发外面)
	_set_or_clear_layer(target_node, portrait_tex, "acc_hat_tex", "acc_hat_rect", "AccHatLayer")

	# 🖼 第八层：照片白边框（比帽子还高一层，保证任何情况下都不被挡）
	_set_frame_layer(target_node, show_frame, emp_rarity)

	# 3. 强制刷新一次所有层级的顺序，确保万无一失
	_reorder_layers(target_node)

	# ==========================================
	# 4. 终极视觉修正：把人物整体（包括新配饰）往上拽！
	# ==========================================
	var y_offset = -12 # 负数代表往上移动。
	
	# 🌟 修正：把 AccGlassesLayer 和 AccHatLayer 也塞进移动大名单里
	var character_layers = [
		"BodyLayer", 
		"ClothesBottomLayer", 
		"ClothesTopLayer", 
		"AccGlassesLayer", 
		"HairLayer", 
		"AccHatLayer"
	]
	for l_name in character_layers:
		var l = target_node.get_node_or_null(l_name)
		if l:
			l.position.y = y_offset

static func _set_or_clear_layer(parent: Control, main_tex: Texture2D, tex_key: String, rect_key: String, layer_name: String):
	var layer = parent.get_node_or_null(layer_name)
	
	if main_tex.has_meta(tex_key) and main_tex.get_meta(tex_key) != null:
		if not layer:
			layer = TextureRect.new()
			layer.name = layer_name
			layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent.add_child(layer)
		
		var atlas = AtlasTexture.new()
		atlas.atlas = main_tex.get_meta(tex_key)
		atlas.region = main_tex.get_meta(rect_key)
		layer.texture = atlas
	elif layer:
		layer.texture = null

static func _clear_layer(parent: Control, layer_name: String):
	var layer = parent.get_node_or_null(layer_name)
	if layer:
		layer.texture = null

# 底图层：按 USE_SOLID_COLOR_BG 在「纯色」与「原插图」之间二选一。
# ⚠️ 两个分支都显式写全 texture / stretch_mode / modulate 三项，
#    这样无论从哪种切到哪种，都不会残留上一种模式的状态。
static func _set_bg_layer(parent: Control, emp_rarity: Employee.Rarity) -> void:
	var layer: TextureRect = parent.get_node_or_null("BgLayer") as TextureRect
	if layer == null:
		layer = _create_layer_node(parent, "BgLayer")

	if USE_SOLID_COLOR_BG:
		layer.texture = _get_white_tex()
		layer.stretch_mode = TextureRect.STRETCH_SCALE
		if USE_BG_PATTERN:
			# 纯色 + 纹理：颜色与花样全部交给 shader，modulate 必须复位成白，
			# 否则会在 shader 结果上再乘一次色，整块变暗。
			layer.material = _get_bg_material(emp_rarity)
			layer.modulate = Color.WHITE
		else:
			# 干净纯色：1×1 白图拉满整块，再用 modulate 染成稀有度对应色
			layer.material = null
			layer.modulate = RARITY_COLORS.get(emp_rarity, Color.WHITE)
	else:
		# 原插图：material / stretch / modulate 一并复位，回到改动前的表现
		layer.material = null
		layer.texture = RARITY_BGS.get(emp_rarity)
		layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		layer.modulate = Color.WHITE

static func _set_direct_layer(parent: Control, tex: Texture2D, layer_name: String):
	var layer = parent.get_node_or_null(layer_name)
	if tex:
		if not layer:
			layer = _create_layer_node(parent, layer_name)
		layer.texture = tex
	elif layer:
		layer.texture = null

static func _set_body_layer(parent: Control, tex: Texture2D, layer_name: String):
	var layer = parent.get_node_or_null(layer_name)
	if tex:
		if not layer:
			layer = TextureRect.new()
			layer.name = layer_name
			layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent.add_child(layer)
		layer.texture = tex
	elif layer:
		layer.texture = null

# 终极保底：强制排序函数
static func _reorder_layers(parent: Control):
	var order = [
		"BgLayer", 
		"BodyLayer", 
		"ClothesBottomLayer", 
		"ClothesTopLayer", 
		"HairLayer",
		"AccGlassesLayer",
		"AccHatLayer",
		FRAME_LAYER          # 白边框永远排最后 = 画在最顶层
	]

	# 🌟 核心修正：不要用固定的 index，因为有些角色没有帽子/眼镜！
	for layer_name in order:
		var layer = parent.get_node_or_null(layer_name)
		if layer:
			# -1 表示“把这个节点移动到当前所有兄弟节点的最下面（也就是视觉的最顶层）”
			# 只要我们按 order 数组的顺序把存在的节点一个个往最后塞，排出来的顺序就绝对正确！
			parent.move_child(layer, -1)

static func _create_layer_node(parent: Control, layer_name: String) -> TextureRect:
	var layer = TextureRect.new()
	layer.name = layer_name
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(layer)
	return layer
