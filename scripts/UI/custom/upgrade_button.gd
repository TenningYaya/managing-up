extends TextureButton

@export_group("NinePatch Background")
@export var bg_normal: Texture2D
@export var bg_pressed: Texture2D

@onready var bg_rect: NinePatchRect = $NinePatchRect

func _ready() -> void:
	add_to_group("upgrade_button")
	if bg_normal:
		bg_rect.texture = bg_normal
	button_down.connect(_on_btn_down)
	button_up.connect(_on_btn_up)
	mouse_exited.connect(_on_btn_up)

func _on_btn_down() -> void:
	if not disabled and bg_pressed:
		bg_rect.texture = bg_pressed

func _on_btn_up() -> void:
	if not disabled and bg_normal:
		bg_rect.texture = bg_normal
