#employee_card.gd

extends Control

signal card_clicked(employee_data: Employee) # 定义信号，把员工数据传出去

# 节点引用 (根据上面的结构定位)
@onready var name_label = $VBoxContainer/NameLabel
@onready var avatar_img = $VBoxContainer/AvatarArea/Avatar
@onready var rarity_label = $VBoxContainer/AvatarArea/RarityLabel

# 三个条
@onready var eff_bar = $VBoxContainer/StatsBars/EfficiencyBar
@onready var qual_bar = $VBoxContainer/StatsBars/QualityBar
@onready var exp_bar = $VBoxContainer/StatsBars/ExperienceBar

@onready var checkmark = $Checkmark
@onready var on_map_icon = $OnMapIcon

var my_employee_data: Employee
var is_selected: bool = false : 
	set(v):
		is_selected = v
		if checkmark: checkmark.visible = v

func _ready():
	# 只要有人被空投，或者有人被开除，就触发自查
	Gamemanager.request_employee_drop.connect(_on_map_changed)
	EmployeeManager.employee_removed.connect(_on_map_changed)

func _on_map_changed(_data = null):
	# 给一点点缓冲时间，等节点彻底 queue_free 掉
	get_tree().create_timer(0.1).timeout.connect(func():
		update_on_map_status(my_employee_data)
	)
	
func setup_card(employee_data: Employee) -> void:
	if employee_data == null: return
	my_employee_data = employee_data
	
	# 1. 设置名字
	name_label.text = employee_data.employee_name
	print(name_label.text)
	
	if employee_data.portrait:
		avatar_img.texture = employee_data.portrait
		# 自动处理头发、衣服等层叠
		_update_avatar_layers(employee_data.portrait)
		
	# 2. 设置头像和等级悬浮标
	match employee_data.rarity:
		Employee.Rarity.R: 
			rarity_label.text = " R "
			rarity_label.add_theme_color_override("font_color", Color.LIGHT_BLUE)
		Employee.Rarity.SR: 
			rarity_label.text = " SR "
			rarity_label.add_theme_color_override("font_color", Color.MEDIUM_PURPLE)
		Employee.Rarity.SSR: 
			rarity_label.text = " SSR "
			rarity_label.add_theme_color_override("font_color", Color.GOLD)
			
	# 如果你有头像图片，可以在这里赋值：
	# avatar_img.texture = employee_data.avatar_texture
	
	# 3. 设置属性条
	eff_bar.max_value = 10
	eff_bar.value = employee_data.efficiency
	
	qual_bar.max_value = 10
	qual_bar.value = employee_data.quality
	
	exp_bar.max_value = 10
	exp_bar.value = employee_data.experience
	
	get_tree().create_timer(0.1).timeout.connect(func(): update_on_map_status(employee_data))
	
func _gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("点中了员工：", my_employee_data.employee_name)
		card_clicked.emit(my_employee_data) # 发射信号
		accept_event() # 拦截点击，防止触发仓库的“点击空白处关闭”

func set_selection_mode(active: bool):
	if not active:
		is_selected = false
		
func update_on_map_status(employee_data_override: Employee = null):
	# 如果没传参数，就用自己存的数据
	var data = employee_data_override if employee_data_override else my_employee_data
	if data == null: return
	
	var is_on_map = false
	
	# 条件 1：如果他有座位，那肯定在地图上（工位上）
	if data.get("current_seat") != null:
		is_on_map = true
		
	# 条件 2：如果没有座位，但他在“掉落组”里，并且确实“在场景树里” (is_inside_tree)
	elif data.is_in_group("dropped_employee") and data.is_inside_tree():
		is_on_map = true
		
	# 控制绿标显示
	on_map_icon.visible = is_on_map

# ---------------------------------------------------------
# 统一层叠显示逻辑 (建议把这段拷贝到所有需要显示员工头像的脚本里)
# ---------------------------------------------------------
func _update_avatar_layers(main_tex: Texture2D):
	_set_or_clear_layer(main_tex, "hair_tex", "hair_rect", "HairLayer")
	_set_or_clear_layer(main_tex, "clothes_tex", "clothes_rect", "ClothesLayer")

func _set_or_clear_layer(main_tex: Texture2D, tex_key: String, rect_key: String, layer_name: String):
	var layer = avatar_img.get_node_or_null(layer_name)
	
	if main_tex.has_meta(tex_key):
		if not layer:
			layer = TextureRect.new()
			layer.name = layer_name
			layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			avatar_img.add_child(layer)
		
		var atlas = AtlasTexture.new()
		atlas.atlas = main_tex.get_meta(tex_key)
		atlas.region = main_tex.get_meta(rect_key)
		layer.texture = atlas
	elif layer:
		layer.texture = null
