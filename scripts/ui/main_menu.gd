extends Node3D

const CHARACTER_SELECT := "res://scenes/ui/character_select.tscn"
const LOBBY := "res://scenes/ui/lobby.tscn"
const ORBIT_SPEED := 0.08
## parado no menu esse tempo, sem nenhum painel aberto, o jogo volta ao teaser, como vitrine
const IDLE_TEASER_SECONDS := 20.0
## o analógico em repouso balança um pouco; abaixo disso não conta como mexer
const STICK_DEADZONE := 0.5

@export var camera_pivot: Node3D
@export var knight_animation: AnimationPlayer
@export var skeleton_animation: AnimationPlayer
@export_file("*.tscn") var idle_scene := "res://scenes/cutscenes/teaser_intro.tscn"

@onready var menu_panel: Control = %MenuPanel
@onready var settings_menu: SettingsMenu = %SettingsMenu
@onready var leaderboard: LeaderboardPanel = %LeaderboardPanel

var idle_seconds := 0.0
var returned_to_teaser := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_why_the_match_ended()
	Net.leave()
	var web := OS.has_feature("web")
	if not web and Net.has_command_line():
		get_tree().change_scene_to_file.call_deferred(LOBBY)
		return
	knight_animation.play("Idle")
	skeleton_animation.play("Idle")
	%PlayButton.pressed.connect(_on_play_pressed)
	var coop_button := %CoopButton as Button
	var leaderboard_button := %LeaderboardButton as Button
	if web:
		coop_button.disabled = true
		coop_button.text = "Grupo só no download"
		coop_button.tooltip_text = "Baixe o jogo para aceitar um contrato em grupo."
		leaderboard_button.disabled = true
		leaderboard_button.text = "Placar só no download"
		leaderboard_button.tooltip_text = "Baixe o jogo para abrir o placar."
	else:
		coop_button.pressed.connect(get_tree().change_scene_to_file.bind(LOBBY))
		leaderboard_button.pressed.connect(_open_leaderboard)
	leaderboard.closed.connect(_close_leaderboard)
	%SettingsButton.pressed.connect(_open_settings)
	%QuitButton.pressed.connect(get_tree().quit)
	settings_menu.closed.connect(_close_settings)
	_focus_for_gamepad(%PlayButton)


# a partida em grupo caiu (sala fechou, host saiu): o jogo volta ao menu e diz por quê
func _show_why_the_match_ended() -> void:
	if Net.last_error.is_empty():
		return
	%Notice.text = Net.last_error
	%Notice.show()
	Net.last_error = ""


func _process(delta: float) -> void:
	camera_pivot.rotation.y += ORBIT_SPEED * delta
	if OS.has_feature("web"):
		return
	# o aviso de partida caída também segura: o motivo some do Net depois de mostrado uma vez
	if not menu_panel.visible or %Notice.visible:
		idle_seconds = 0.0
		return
	idle_seconds += delta
	if idle_seconds >= IDLE_TEASER_SECONDS:
		_return_to_teaser()


## qualquer mexida conta, mesmo a que um botão consome antes de chegar aqui
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion and absf(event.axis_value) < STICK_DEADZONE:
		return
	if event is InputEventKey or event is InputEventMouse or event is InputEventJoypadButton or event is InputEventJoypadMotion or event is InputEventScreenTouch:
		idle_seconds = 0.0


func _return_to_teaser() -> void:
	if returned_to_teaser:
		return
	returned_to_teaser = true
	if not idle_scene.is_empty():
		get_tree().change_scene_to_file(idle_scene)


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(CHARACTER_SELECT)


func _open_leaderboard() -> void:
	menu_panel.hide()
	leaderboard.open()


func _close_leaderboard() -> void:
	menu_panel.show()
	_focus_for_gamepad(%LeaderboardButton)


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
