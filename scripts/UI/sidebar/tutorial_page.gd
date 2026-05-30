extends Control

@onready var scroll_container = $ScrollContainer

func _ready() -> void:
	scroll_container.custom_minimum_size.x = 200
	scroll_container.size.x = 200

func _process(delta: float) -> void:
	pass
