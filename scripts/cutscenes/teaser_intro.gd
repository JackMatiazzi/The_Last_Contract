extends Control
## Abre o jogo com o teaser e segue para o menu quando o vídeo acaba ou o jogador pula.
## Sem o vídeo, ou aberto pela linha de comando (testes e2e, co-op automático), vai direto ao menu

@export_file("*.ogv") var teaser_path := "res://assets/video/teaser-tlc.ogv"
@export_file("*.tscn") var next_scene := "res://scenes/ui/main_menu.tscn"

@onready var video: VideoStreamPlayer = %Teaser

var leaving := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not Net.has_command_line() and ResourceLoader.exists(teaser_path):
		video.stream = load(teaser_path) as VideoStream
		if video.stream:
			video.play()
	if not video.is_playing():
		_open_menu.call_deferred()


## roda do mouse e movimento não pulam: só clique, tecla, botão do controle ou toque
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
	if leaving:
		return
	leaving = true
	video.stop()
	if not next_scene.is_empty():
		get_tree().change_scene_to_file(next_scene)
