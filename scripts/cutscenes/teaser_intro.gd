extends Control

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const TEASER := "res://assets/video/teaser-tlc.ogv"

@onready var video: VideoStreamPlayer = %Teaser

var _leaving := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not Net.has_command_line() and ResourceLoader.exists(TEASER):
		video.stream = load(TEASER) as VideoStream
		if video.stream:
			video.play()
	if not video.is_playing():
		_open_menu.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event is InputEventMouseButton:
		if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			return
	elif not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventScreenTouch):
		return
	get_viewport().set_input_as_handled()
	_open_menu()


func _open_menu() -> void:
	if _leaving:
		return
	_leaving = true
	video.stop()
	get_tree().change_scene_to_file(MAIN_MENU)
