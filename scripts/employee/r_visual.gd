extends Node2D

# 告诉代码我们要操作哪个图片节点
@onready var body: Sprite2D = $Body

# 这里建了一个叫 Array 的“大箱子”，专门用来装所有的 R 卡图片
@export var r_character_pictures: Array[Texture2D] = []

# 游戏生成员工时，会自动运行这个 setup_visual 函数
func setup_visual(_seed: int, _style_data: Dictionary) -> void:
	if body == null: body = get_node("Body")
		
	if not r_character_pictures.is_empty():
		# 🌟 基因系统改造
		var tex_idx = _style_data.get("tex_idx", randi() % r_character_pictures.size())
		_style_data["tex_idx"] = tex_idx # 保存回字典
		
		body.texture = r_character_pictures[tex_idx]
		body.hframes = 3  
		body.vframes = 4  

	self.position = Vector2(55, 10)
	self.scale = Vector2(3.5, 3.5)

# 专门给 RecruitmentManager 调用的头像生成逻辑
func generate_portrait_texture() -> Texture2D:
	var atlas = AtlasTexture.new()
	# 确保节点已经醒了
	if body == null: body = get_node("Body")
		
	if body != null and body.texture != null:
		atlas.atlas = body.texture
		
		# 自动计算每一格的宽度和高度（这样不管美术给多大的图都能自动切好）
		var frame_width = body.texture.get_width() / body.hframes
		var frame_height = body.texture.get_height() / body.vframes
		
		# 永远只切第 1 格（最左边）的画面作为头像
		atlas.region = Rect2(0, 0, frame_width, frame_height)
		
	return atlas
