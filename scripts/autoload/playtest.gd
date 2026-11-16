extends Node
## registro de cada contrato para o playtest com os colegas: um .json por partida em user://playtest.
## so grava na build exportada ou com --playtest, para os testes e o editor nao encherem a pasta.
## Quem aceitou participar tambem manda o resumo ao servidor (TelemetryUplink)

const DIR := "user://playtest"
## sem mexer por mais que isso, o tempo não conta para nenhum dispositivo (lendo bilhete, parado, longe do PC)
const IDLE_AFTER := 2.0
const GAMEPAD := "controle"
const KEYBOARD_MOUSE := "teclado_mouse"
const STICK_HELD := 0.5
const STICKS: Array[JoyAxis] = [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]

var enabled := OS.has_feature("template") or "--playtest" in OS.get_cmdline_user_args()
var directory := DIR
var last_path := ""
var _run := {}
var _started_msec := 0
var _device_seconds := {}
var _last_device := ""
var _last_input_msec := 0
var uplink := TelemetryUplink.new()


func _ready() -> void:
	uplink.name = "Uplink"
	# a tela de morte e o menu pausam o jogo; o envio continua, senao a resposta fica parada ate voltar
	uplink.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(uplink)
	# fechar pela janela tambem fecha o contrato e espera o ultimo envio antes de sair
	get_tree().auto_accept_quit = false
	_apply_test_arguments()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()


func _quit() -> void:
	finish("quit")
	await uplink.wait_until_idle(TelemetryUplink.QUIT_WAIT_SECONDS)
	get_tree().quit()


# so para os testes ponta a ponta: aceitar e definir um contato sem passar pela tela de aviso
func _apply_test_arguments() -> void:
	if not "--playtest" in OS.get_cmdline_user_args():
		return
	for arg in OS.get_cmdline_user_args():
		if arg == "--aceitar-telemetria":
			uplink.test_code = Settings.new_player_code()
		elif arg.begins_with("--contato="):
			uplink.contact = arg.trim_prefix("--contato=")


func is_solo() -> bool:
	return is_running() and int(_run.get("players", 1)) == 1 and not Net.is_coop()


func is_running() -> bool:
	return not _run.is_empty()


func start_run(adventurer: String, players: int, level: String) -> void:
	if not enabled:
		return
	_started_msec = Time.get_ticks_msec()
	_device_seconds = {GAMEPAD: 0.0, KEYBOARD_MOUSE: 0.0}
	_last_device = ""
	var started_at := Time.get_datetime_string_from_system()
	# o peer separa as instancias de um co-op aberto na mesma maquina
	var file_name := "%s_%s_p%d_%03d.json" % [started_at.replace(":", "-"), adventurer.to_snake_case(), multiplayer.get_unique_id(), _started_msec % 1000]
	last_path = directory.path_join(file_name)
	_run = {
		"started_at": started_at,
		"version": ProjectSettings.get_setting("application/config/version", ""),
		"adventurer": adventurer,
		"players": players,
		"level": level,
		"result": "",
		"events": [],
	}
	_save()
	if is_solo():
		uplink.open_solo(_run)


func record(kind: String, data := {}) -> void:
	if not is_running():
		return
	var event := data.merged({"type": kind, "t": elapsed(), "attempt": RunState.attempt})
	_run["events"].append(event)
	_save()
	if is_solo() and kind in TelemetryUplink.MILESTONES:
		uplink.milestone(_run)


## fecha o arquivo: o proximo contrato abre outro
func finish(result: String) -> void:
	if not is_running():
		return
	record(result, device_usage())
	_run["result"] = result
	_run["duration"] = elapsed()
	_save()
	if is_solo():
		uplink.close_solo(_run, result)
	else:
		uplink.send_coop(_run, result)
	_run = {}


## o dispositivo mais usado na partida e quanto do tempo jogado foi no controle; vazio se ninguém mexeu
func device_usage() -> Dictionary:
	var total: float = _device_seconds.get(GAMEPAD, 0.0) + _device_seconds.get(KEYBOARD_MOUSE, 0.0)
	if total <= 0.0:
		return {}
	var share: float = _device_seconds[GAMEPAD] / total
	return {"device": GAMEPAD if share > 0.5 else KEYBOARD_MOUSE, "gamepad_share": snappedf(share, 0.01)}


func _input(event: InputEvent) -> void:
	if not is_running():
		return
	var gamepad: bool = event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > STICK_HELD)
	var moved_mouse: bool = event is InputEventMouseMotion and event.screen_relative.length() > Settings.MOUSE_SWITCH_DISTANCE
	if gamepad:
		_touch(GAMEPAD)
	elif event is InputEventKey or event is InputEventMouseButton or moved_mouse:
		_touch(KEYBOARD_MOUSE)


# analógico parado inclinado e tecla segurada não geram evento novo, mas o jogador continua jogando
func _process(delta: float) -> void:
	if not is_running():
		return
	if _gamepad_held():
		_touch(GAMEPAD)
	elif Input.is_anything_pressed() and not _last_device.is_empty():
		_last_input_msec = Time.get_ticks_msec()
	if not _last_device.is_empty() and Time.get_ticks_msec() - _last_input_msec <= IDLE_AFTER * 1000.0:
		_device_seconds[_last_device] += delta


func _touch(device: String) -> void:
	_last_device = device
	_last_input_msec = Time.get_ticks_msec()


static func _gamepad_held() -> bool:
	for pad in Input.get_connected_joypads():
		for axis in STICKS:
			if absf(Input.get_joy_axis(pad, axis)) > STICK_HELD:
				return true
	return false


func elapsed() -> float:
	return snappedf((Time.get_ticks_msec() - _started_msec) / 1000.0, 0.1)


func position_of(node: Node3D) -> Array:
	return [snappedf(node.global_position.x, 0.1), snappedf(node.global_position.y, 0.1), snappedf(node.global_position.z, 0.1)]


# grava a cada evento: se o jogo fechar no meio, o que aconteceu ate ali fica salvo
func _save() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(last_path, FileAccess.WRITE)
	if file == null:
		push_warning("Playtest: nao deu para gravar %s (%s)" % [last_path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(_run, "\t"))
