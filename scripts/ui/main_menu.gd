extends Node3D

const CHARACTER_SELECT := "res://scenes/ui/character_select.tscn"
const LOBBY := "res://scenes/ui/lobby.tscn"
const ORBIT_SPEED := 0.08

@export var camera_pivot: Node3D
@export var knight_animation: AnimationPlayer
@export var skeleton_animation: AnimationPlayer

@onready var menu_panel: Control = %MenuPanel
@onready var settings_menu: SettingsMenu = %SettingsMenu


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Net.leave()
	if Net.has_command_line():
		get_tree().change_scene_to_file.call_deferred(LOBBY)
		return
	knight_animation.play("Idle")
	skeleton_animation.play("Idle")
	%PlayButton.pressed.connect(_on_play_pressed)
	%CoopButton.pressed.connect(get_tree().change_scene_to_file.bind(LOBBY))
	%SettingsButton.pressed.connect(_open_settings)
	%QuitButton.pressed.connect(get_tree().quit)
	settings_menu.closed.connect(_close_settings)
	_focus_for_gamepad(%PlayButton)


func _process(delta: float) -> void:
	camera_pivot.rotation.y += ORBIT_SPEED * delta


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(CHARACTER_SELECT)


func _open_settings() -> void:
	menu_panel.hide()
	settings_menu.open()


func _close_settings() -> void:
	menu_panel.show()
	_focus_for_gamepad(%SettingsButton)


## no mouse o clique deixaria o botao marcado; o foco so serve para navegar pelo controle
func _focus_for_gamepad(button: Control) -> void:
	if Settings.uses_gamepad():
		button.grab_focus()
	else:
		get_viewport().gui_release_focus()


# sem foco, a primeira seta do teclado escolhe o primeiro botao
func _unhandled_input(event: InputEvent) -> void:
	if menu_panel.visible and get_viewport().gui_get_focus_owner() == null and (event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up")):
		%PlayButton.grab_focus()
		get_viewport().set_input_as_handled()
