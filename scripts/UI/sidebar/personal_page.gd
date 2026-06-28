# personal_page.gd
# 挂在 PersonalPage 根节点上，统管：改项目组名字、换头像、中英称呼显隐。
# 信号都在 _ready 里自动连，你只需要在 Inspector 把下面这些节点拖进对应槽位即可。
extends Control

# ---- 名字行（Label + 铅笔图标 + 隐藏的 LineEdit）----
@export var name_label: Label        # 平时显示项目组名字
@export var name_edit: LineEdit      # 编辑用，平时 visible=off
@export var edit_button: BaseButton  # 铅笔图标，点它进入编辑

# ---- 头像（仿 TileChanger：按钮显示当前头像，点开展开选项）----
@export var avatar_button: Button     # 显示当前头像、点击展开/收起选项
@export var avatar_options: Container  # 展开/收起的那一坨（可以是带黑底的 PanelContainer），平时 visible=off
@export var avatar_options_grid: Container  # 头像按钮实际放进哪（PanelContainer 里的 HBox/Grid）；留空则等于 avatar_options
@export var avatar_textures: Array[Texture2D] = []  # 可选头像列表（和 select_avatar 用同一批）

# ---- 称呼（英文显示在头像左，中文显示在头像右，按语言二选一）----
@export var mr_en: Label  # 英文称呼，如 "Leader"
@export var mr_ch: Label  # 中文称呼，如 "领导"

const AVATAR_BTN_SIZE := Vector2(50, 50)

func _ready() -> void:
	# 名字
	if name_edit:
		name_edit.hide()
		name_edit.text_submitted.connect(func(_t): _commit_name())  # 回车确认
		name_edit.focus_exited.connect(_commit_name)                # 点别处确认
	if edit_button:
		edit_button.pressed.connect(_start_name_edit)
	_refresh_name_label()

	# 头像
	if avatar_options:
		avatar_options.hide()
	if avatar_button:
		avatar_button.pressed.connect(_toggle_avatar_options)
	_build_avatar_options()
	_refresh_avatar_button()

	# 称呼按当前语言显隐
	_refresh_title_labels()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_title_labels()
	# 面板每次重新可见时，与存档保持同步（别处改过名字/头像、或删档后）
	elif what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready() and is_visible_in_tree():
		if not (name_edit and name_edit.visible):
			_refresh_name_label()
		_refresh_avatar_button()
		_refresh_title_labels()

# ==================== 项目组名字 ====================
func _current_name() -> String:
	return Gamemanager.project_name if Gamemanager.project_name != "" else tr("DEFAULT_PROJECT_NAME")

func _refresh_name_label() -> void:
	if name_label:
		name_label.text = _current_name()

func _start_name_edit() -> void:
	if not (name_label and name_edit):
		return
	name_edit.text = Gamemanager.project_name
	name_label.hide()
	if edit_button:
		edit_button.hide()
	name_edit.show()
	name_edit.grab_focus()
	name_edit.caret_column = name_edit.text.length()

func _commit_name() -> void:
	# 回车与失焦可能各触发一次，靠 visible 当幂等锁，只执行一次
	if not name_edit or not name_edit.visible:
		return
	var new_name := name_edit.text.strip_edges()
	if new_name != "":
		Gamemanager.project_name = new_name
	name_edit.hide()
	if name_label:
		name_label.show()
	if edit_button:
		edit_button.show()
	_refresh_name_label()
	_save()

# ==================== 头像 ====================
func _toggle_avatar_options() -> void:
	if avatar_options:
		avatar_options.visible = not avatar_options.visible

func _options_parent() -> Node:
	# 按钮放进内层网格（带黑底时是 PanelContainer 里的那个 HBox/Grid）；没单独指定就放进 avatar_options 自己
	return avatar_options_grid if avatar_options_grid else avatar_options

func _build_avatar_options() -> void:
	var parent := _options_parent()
	if not parent:
		return
	for c in parent.get_children():
		c.queue_free()
	for i in avatar_textures.size():
		var btn := TextureButton.new()
		btn.texture_normal = avatar_textures[i]
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_SCALE
		btn.custom_minimum_size = AVATAR_BTN_SIZE
		btn.pressed.connect(_on_avatar_chosen.bind(i))
		parent.add_child(btn)

	# 🌟 末尾追加"+"按钮:半透明白底 + 灰色加号(代码绘制,无需素材),常驻不变。
	#    点它走系统文件框上传自定义头像。
	var add_btn := Button.new()
	add_btn.name = "AddCustomAvatar"
	add_btn.text = "+"
	add_btn.custom_minimum_size = AVATAR_BTN_SIZE
	add_btn.focus_mode = Control.FOCUS_NONE
	add_btn.add_theme_font_size_override("font_size", 30)
	add_btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	add_btn.add_theme_color_override("font_hover_color", Color(0.4, 0.4, 0.4))
	add_btn.add_theme_color_override("font_pressed_color", Color(0.35, 0.35, 0.35))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.5)   # 半透明白底
	sb.set_corner_radius_all(6)
	add_btn.add_theme_stylebox_override("normal", sb)
	add_btn.add_theme_stylebox_override("hover", sb)
	add_btn.add_theme_stylebox_override("pressed", sb)
	add_btn.add_theme_stylebox_override("focus", sb)
	add_btn.pressed.connect(_on_add_custom_avatar)
	parent.add_child(add_btn)

func _on_avatar_chosen(index: int) -> void:
	if index < 0 or index >= avatar_textures.size():
		return
	# 直接写入存档数据并保存（不复用 select_avatar，避免它的 _ready 把头像重置成默认值）
	Gamemanager.player_avatar_index = index
	Gamemanager.player_avatar_texture = avatar_textures[index]
	Gamemanager.player_avatar_is_custom = false   # 选了内置头像 → 清掉自定义状态
	_refresh_avatar_button()
	if avatar_options:
		avatar_options.hide()
	_save()

# ==================== 自定义头像（玩家上传） ====================
const CUSTOM_AVATAR_PATH := "user://player_avatar.png"
const CUSTOM_AVATAR_SIZE := 256

func _on_add_custom_avatar() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG):
		printerr("[PersonalPage] 当前平台不支持系统文件对话框，无法上传自定义头像")
		return
	var title := "选择头像" if TranslationServer.get_locale().begins_with("zh") else "Choose Avatar"
	DisplayServer.file_dialog_show(
		title,
		OS.get_system_dir(OS.SYSTEM_DIR_PICTURES),   # 默认从“图片”文件夹打开
		"",
		false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp"]),
		_on_custom_avatar_picked
	)

func _on_custom_avatar_picked(status: bool, paths: PackedStringArray, _filter_index: int) -> void:
	if not status or paths.is_empty():
		return
	var img := Image.new()
	if img.load(paths[0]) != OK:
		printerr("[PersonalPage] 图片读取失败：", paths[0])
		return
	# MVP：不裁剪，非正方形直接压扁成固定方形
	img.resize(CUSTOM_AVATAR_SIZE, CUSTOM_AVATAR_SIZE, Image.INTERPOLATE_LANCZOS)
	# 落地到固定文件（覆盖式），供存档持久化
	img.save_png(CUSTOM_AVATAR_PATH)
	# 设为当前头像
	Gamemanager.player_avatar_texture = ImageTexture.create_from_image(img)
	Gamemanager.player_avatar_is_custom = true
	Gamemanager.player_avatar_index = -1
	Gamemanager.has_selected_avatar = true
	_refresh_avatar_button()
	if avatar_options:
		avatar_options.hide()
	_save()

func _refresh_avatar_button() -> void:
	if not avatar_button:
		return
	var tex: Texture2D = Gamemanager.player_avatar_texture
	if tex == null and avatar_textures.size() > 0:
		tex = avatar_textures[clampi(Gamemanager.player_avatar_index, 0, avatar_textures.size() - 1)]
	avatar_button.icon = tex
	avatar_button.expand_icon = true
	avatar_button.custom_minimum_size = AVATAR_BTN_SIZE

# ==================== 称呼显隐 ====================
func _refresh_title_labels() -> void:
	var is_zh := TranslationServer.get_locale().begins_with("zh")
	if mr_en:
		mr_en.visible = not is_zh  # 英文：Leader 在头像左
	if mr_ch:
		mr_ch.visible = is_zh      # 中文：领导 在头像右

# ==================== 存档 ====================
func _save() -> void:
	if SaveManager and SaveManager.has_method("save_game"):
		SaveManager.save_game()
