#avatar_name_changer.gd
extends Control

#@onready var sentence_box: HBoxContainer = $SentenceBox
#
#var _name_btn: LinkButton = null
#var _avatar_btn: TextureButton = null
#
#const AVATAR_HEIGHT = 20  # 和字号保持一致
#
#func _ready() -> void:
	#await get_tree().process_frame  # 等父节点算好尺寸
	#sentence_box.custom_minimum_size.x = get_parent().size.x
	#_build_sentence()
#
#func _build_sentence() -> void:
	#for child in sentence_box.get_children():
		#child.queue_free()
	#_name_btn = null
	#_avatar_btn = null
#
	#var format: String = tr("Sidebar_personal_name_avatar")
	#var remaining := format
#
	#while remaining.length() > 0:
		#var np = remaining.find("{name}")
		#var ap = remaining.find("{avatar}")
#
		## 找最近的占位符
		#var next_pos := -1
		#var next_type := ""
		#if np == -1 and ap == -1:
			#_add_label(remaining)
			#break
		#elif np == -1 or (ap != -1 and ap < np):
			#next_pos = ap; next_type = "avatar"
		#else:
			#next_pos = np; next_type = "name"
#
		#if next_pos > 0:
			#_add_label(remaining.substr(0, next_pos))
#
		#if next_type == "name":
			#_name_btn = LinkButton.new()
			#_name_btn.text = Gamemanager.project_name if Gamemanager.project_name != "" else "???"
			#_name_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			#_name_btn.pressed.connect(_open_name_popup)
			#sentence_box.add_child(_name_btn)
			#remaining = remaining.substr(next_pos + 6)  # len("{name}") == 6
		#else:
			#_avatar_btn = TextureButton.new()
			#_avatar_btn.texture_normal = Gamemanager.player_avatar_texture
			#_avatar_btn.ignore_texture_size = true
			#_avatar_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			#_avatar_btn.stretch_mode = TextureButton.STRETCH_SCALE
			#_avatar_btn.custom_minimum_size = Vector2(AVATAR_HEIGHT, AVATAR_HEIGHT)
			#_avatar_btn.pressed.connect(_open_avatar_popup)
			#sentence_box.add_child(_avatar_btn)
			#remaining = remaining.substr(next_pos + 8)  # len("{avatar}") == 8
#
#func _add_label(text: String) -> void:
	#var lbl := Label.new()
	#lbl.text = text
	##lbl.add_theme_font_override("font", preload("res://assets/fonts/Stacked pixel.ttf"))
	##lbl.add_theme_font_size_override("font_size", 16)
	#sentence_box.add_child(lbl)
#
#func _open_name_popup() -> void:
	#var popup = get_tree().get_first_node_in_group("name_program")
	#if popup:
		#popup.show()
		#if not popup.confirmed.is_connected(_on_name_confirmed):
			#popup.confirmed.connect(_on_name_confirmed)
		#if not popup.canceled.is_connected(popup.hide):
			#popup.canceled.connect(popup.hide)
#
#func _open_avatar_popup() -> void:
	#var popup = get_tree().get_first_node_in_group("select_avatar")
	#if popup:
		#popup.show()
		#if not popup.confirmed.is_connected(_on_avatar_confirmed):
			#popup.confirmed.connect(_on_avatar_confirmed)
#
#func _on_name_confirmed(new_name: String) -> void:
	#Gamemanager.project_name = new_name
	#var popup = get_tree().get_first_node_in_group("name_program")
	#if popup:
		#popup.hide()
	#if _name_btn:
		#_name_btn.text = new_name
#
#func _on_avatar_confirmed(index: int) -> void:
	#Gamemanager.player_avatar_index = index
	#var popup = get_tree().get_first_node_in_group("select_avatar")
	#if popup:
		#Gamemanager.player_avatar_texture = popup.avatar_textures[index]
		#popup.hide()
	#if _avatar_btn:
		#_avatar_btn.texture_normal = Gamemanager.player_avatar_texture
#avatar_name_changer.gd
@onready var rich_label: RichTextLabel = $SentenceBox

func _ready() -> void:
	_build_sentence()

func _build_sentence() -> void:
	rich_label.bbcode_enabled = true
	rich_label.fit_content = true
	rich_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	if rich_label.meta_clicked.is_connected(_on_meta_clicked):
		rich_label.meta_clicked.disconnect(_on_meta_clicked)
	rich_label.meta_clicked.connect(_on_meta_clicked)

	var project_name := Gamemanager.project_name if Gamemanager.project_name != "" else "???"
	var format := tr("Sidebar_personal_name_avatar")

	var name_bbcode := "[color=#6699ff][u][url=name]%s[/url][/u][/color]" % project_name

	var avatar_path := _get_avatar_path()
	var avatar_bbcode := ""
	if avatar_path != "":
		avatar_bbcode = "[url=avatar][img=20x20]%s[/img][/url]" % avatar_path
	else:
		avatar_bbcode = "[url=avatar]○[/url]"

	rich_label.text = format.replace("{name}", name_bbcode).replace("{avatar}", avatar_bbcode)

func _get_avatar_path() -> String:
	if Gamemanager.player_avatar_texture and Gamemanager.player_avatar_texture.resource_path != "":
		return Gamemanager.player_avatar_texture.resource_path
	return ""

func _on_meta_clicked(meta: Variant) -> void:
	if meta == "name":
		_open_name_popup()
	elif meta == "avatar":
		_open_avatar_popup()

func _open_name_popup() -> void:
	var popup = get_tree().get_first_node_in_group("name_program")
	if popup:
		popup.refresh_cancel_btn()  # 👈 每次打开前刷新
		popup.show()
		if not popup.confirmed.is_connected(_on_name_confirmed):
			popup.confirmed.connect(_on_name_confirmed)
		if not popup.canceled.is_connected(popup.hide):
			popup.canceled.connect(popup.hide)

func _open_avatar_popup() -> void:
	var popup = get_tree().get_first_node_in_group("select_avatar")
	if popup:
		popup.show()
		if not popup.confirmed.is_connected(_on_avatar_confirmed):
			popup.confirmed.connect(_on_avatar_confirmed)

func _on_name_confirmed(new_name: String) -> void:
	Gamemanager.project_name = new_name
	var popup = get_tree().get_first_node_in_group("name_program")
	if popup:
		popup.hide()
	_build_sentence()

func _on_avatar_confirmed(index: int) -> void:
	Gamemanager.player_avatar_index = index
	var popup = get_tree().get_first_node_in_group("select_avatar")
	if popup:
		Gamemanager.player_avatar_texture = popup.avatar_textures[index]
		popup.hide()
	_build_sentence()
