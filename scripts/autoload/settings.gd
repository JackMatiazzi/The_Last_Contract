extends Node
## Gerenciador de configurações de jogo e preferências do usuário (Autoload).
## Controla volume do áudio, exibição de tela, sensibilidade dos controles,
## salvamento/carregamento no arquivo 'user://settings.cfg' e alternância dinâmica entre Teclado e Controle.

## Emitido quando o dispositivo de entrada ativo altera (ex: de Teclado/Mouse para Gamepad).
signal input_device_changed
## Tipos de controle suportados pelo jogo.
enum InputDevice { KEYBOARD_MOUSE, GAMEPAD, AUTOMATIC }
## Caminho do arquivo de configuração do usuário no disco.
const PATH := "user://settings.cfg"
## tremida do mouse na mesa nao tira do modo controle
const MOUSE_SWITCH_DISTANCE := 4.0
const SECTION := "settings"
## Mapeamento de ações de entrada usadas na jogabilidade que serão reconfiguradas no InputMap.
const GAMEPLAY_ACTIONS := ["move_forward", "move_back", "move_left", "move_right", "attack", "secondary",
		"run", "look_left", "look_right", "look_up", "look_down", "interact", "decline", "scoreboard",
		"next_ability", "next_item"]
## quem nunca assinou o contrato aparece assim
const DEFAULT_PLAYER_NAME := "Aventureiro"
## escolha sobre enviar o resumo das partidas ao servidor: ainda não perguntado, aceitou ou recusou
const CONSENT_UNSET := 0
const CONSENT_YES := 1
const CONSENT_NO := 2

enum GraphicsMode { QUALITY, PERFORMANCE }
## o Godot lê este arquivo antes de abrir a janela (application/config/project_settings_override); é o
## único jeito de trocar o renderizador, então a troca de gráficos só vale quando o jogo abre de novo
const GRAPHICS_OVERRIDE := "user://graficos.cfg"
const PERFORMANCE_RENDERER := "gl_compatibility"

var master_volume := 1.0
var music_volume := 0.8
var sfx_volume := 1.0
var fullscreen := false
var vsync := true
var mouse_sensitivity := 1.0
var invert_y := false
## mouse e teclado por padrão; o controle se escolhe em Configurações > Controles
var input_device := InputDevice.KEYBOARD_MOUSE
var stick_sensitivity := 1.0
var player_name := DEFAULT_PLAYER_NAME
var telemetry_consent := CONSENT_UNSET
## Qualidade usa o Forward+ (névoa volumétrica, brilho e luzes sem limite por objeto); Desempenho, o
## Compatibility, que roda em vídeo integrado fraco
var graphics_mode := GraphicsMode.QUALITY
var graphics_override_path := GRAPHICS_OVERRIDE
## código aleatório deste PC, criado só quando o jogador aceita: liga as partidas dele no painel sem
## nome nem identificador do aparelho. Recusar apaga o código
var player_code := ""

var _applied_device := -1
var _last_used_gamepad := false


func _ready() -> void:
	# Mantém este nó ativo mesmo durante a pausa do jogo para responder a mudanças nos menus
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	_apply()
	# o settings.cfg manda: um graficos.cfg que sobrou ou sumiu volta a bater com a escolha salva
	_write_graphics_override()

## Atualiza o valor de uma propriedade, aplica as alterações no jogo e salva no disco.
func set_value(key: StringName, value: Variant) -> void:
	set(key, value)
	_apply()
	_save()
	if key == &"graphics_mode":
		_write_graphics_override()


## a escolha salva difere do renderizador em uso: vale ao reabrir o jogo
func graphics_restart_needed() -> bool:
	var running_performance := RenderingServer.get_current_rendering_method() == PERFORMANCE_RENDERER
	return running_performance != (graphics_mode == GraphicsMode.PERFORMANCE)


func restart_game() -> void:
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	get_tree().quit()


func _write_graphics_override() -> void:
	if graphics_mode == GraphicsMode.QUALITY:
		if FileAccess.file_exists(graphics_override_path):
			var removed := DirAccess.remove_absolute(ProjectSettings.globalize_path(graphics_override_path))
			if removed != OK:
				push_error("Nao foi possivel voltar ao modo de qualidade: %s" % error_string(removed))
		return
	var config := ConfigFile.new()
	config.set_value("rendering", "renderer/rendering_method", PERFORMANCE_RENDERER)
	var error := config.save(graphics_override_path)
	if error != OK:
		push_error("Nao foi possivel salvar o modo de desempenho: %s" % error_string(error))

## Aplica as configurações ativas nos barramentos de áudio, janela, vsync e mapa de inputs.
func _apply() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	if input_device != _applied_device:
		_applied_device = input_device
		_apply_input_device()
		input_device_changed.emit()

## Retorna true se o dispositivo atualmente em uso for um controle/gamepad.
func uses_gamepad() -> bool:
	if input_device == InputDevice.AUTOMATIC:
		return _last_used_gamepad
	return input_device == InputDevice.GAMEPAD

## Monitora os inputs em tempo real para alternar automaticamente entre Teclado/Mouse e Controle.
func _input(event: InputEvent) -> void:
	if input_device != InputDevice.AUTOMATIC:
		return
	var gamepad: bool = _is_gamepad_event(event) and (event is InputEventJoypadButton or absf(event.axis_value) > 0.5)
	var moved_mouse: bool = event is InputEventMouseMotion and event.screen_relative.length() > MOUSE_SWITCH_DISTANCE
	var keyboard_mouse: bool = event is InputEventKey or event is InputEventMouseButton or moved_mouse
	if (gamepad and not _last_used_gamepad) or (keyboard_mouse and _last_used_gamepad):
		_last_used_gamepad = gamepad
		input_device_changed.emit()


# le do project.godot porque o InputMap ja esta filtrado e perderia o outro dispositivo
func _apply_input_device() -> void:
	for action: String in GAMEPLAY_ACTIONS:
		InputMap.action_erase_events(action)
		for event: InputEvent in ProjectSettings.get_setting("input/" + action)["events"]:
			if input_device == InputDevice.AUTOMATIC or _is_gamepad_event(event) == uses_gamepad():
				InputMap.action_add_event(action, event)


static func _is_gamepad_event(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


func _set_bus_volume(bus: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index != -1:
		AudioServer.set_bus_volume_db(index, linear_to_db(linear))


func _keys() -> PackedStringArray:
	return ["master_volume", "music_volume", "sfx_volume", "fullscreen", "vsync", "mouse_sensitivity", "invert_y", "input_device", "stick_sensitivity", "player_name", "telemetry_consent", "player_code", "graphics_mode"]

## desligar só para de enviar: o código fica, para o jogador ainda poder apagar o que já mandou
func accept_telemetry(accepted: bool) -> void:
	telemetry_consent = CONSENT_YES if accepted else CONSENT_NO
	if accepted and player_code.is_empty():
		player_code = new_player_code()
	_save()


## depois que o servidor apagou os dados: o código some e um aceite futuro cria outro
func forget_player_code() -> void:
	player_code = ""
	_save()


func new_player_code() -> String:
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(16).hex_encode()


## Carrega as configurações salvas no arquivo 'user://settings.cfg'.
func _load() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	for key in _keys():
		set(key, config.get_value(SECTION, key, get(key)))

## Salva o estado atual das variáveis de configuração no arquivo 'user://settings.cfg'.
func _save() -> void:
	var config := ConfigFile.new()
	for key in _keys():
		config.set_value(SECTION, key, get(key))
	var error := config.save(PATH)
	if error != OK:
		push_error("Nao foi possivel salvar as configuracoes: %s" % error_string(error))
