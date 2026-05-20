# tutorial_blocker.gd
# 🌟 削权后的纯净版：只负责生成 4 块布和挖洞，不写死任何逻辑！
extends Control

var curtain_top: ColorRect
var curtain_bottom: ColorRect
var curtain_left: ColorRect
var curtain_right: ColorRect

var hole_rect: Rect2 = Rect2()
var mask_color = Color(0, 0, 0, 0.5) # 幕布颜色：50%透明纯黑

var is_hole_clickable: bool = true

func _ready() -> void:
	# 游戏刚开局时，默默在后台把 4 块布建好，然后隐身等总管召唤
	_create_curtains()
	hide()

# ==========================================
# 核心功能 1：建布
# ==========================================
func _create_curtains() -> void:
	curtain_top = _spawn_color_rect("CurtainTop")
	curtain_bottom = _spawn_color_rect("CurtainBottom")
	curtain_left = _spawn_color_rect("CurtainLeft")
	curtain_right = _spawn_color_rect("CurtainRight")

func _spawn_color_rect(rect_name: String) -> ColorRect:
	var cr = ColorRect.new()
	cr.name = rect_name
	cr.color = mask_color
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE # 儿子不拦，老子拦
	add_child(cr)
	return cr

# ==========================================
# 核心功能 2：听从大总管的命令去排布位置
# ==========================================
func _arrange_curtains(rect: Rect2) -> void:
	# 记下现在的洞在哪里
	hole_rect = rect 
	var screen_size = get_viewport_rect().size
	
	curtain_top.global_position = Vector2(0, 0)
	curtain_top.size = Vector2(screen_size.x, rect.position.y)
	
	curtain_bottom.global_position = Vector2(0, rect.end.y)
	curtain_bottom.size = Vector2(screen_size.x, screen_size.y - rect.end.y)
	
	curtain_left.global_position = Vector2(0, rect.position.y)
	curtain_left.size = Vector2(rect.position.x, rect.size.y)
	
	curtain_right.global_position = Vector2(rect.end.x, rect.position.y)
	curtain_right.size = Vector2(screen_size.x - rect.end.x, rect.size.y)

# ==========================================
# 核心功能 3：负责物理拦截
# ==========================================
func _has_point(point: Vector2) -> bool:
	if hole_rect == Rect2():
		return true # 没挖洞的时候，全屏拦死
		
	var global_mouse_pos = global_position + point
	
	if hole_rect.has_point(global_mouse_pos):
		# 如果大总管不让点，我们就把这个洞当成实心的，继续拦截（返回 true）
		if not is_hole_clickable:
			return true 
		# 如果允许点击，就放行（返回 false），让底下的按钮响应
		return false
		
	return true # 点在黑布上，拦死
