extends "res://tests/e2e/e2e_driver.gd"

# partida de carga pela sala online: cada processo e um jogador controlado por um bot que anda, corre,
# gira a camera, ataca, para como quem le um bilhete, cai e vota, com os inimigos de IA ligada.
# Serve para medir no banco da API (GET /uso) quantas requisicoes uma partida inteira gasta antes do deploy.
# --minutos=N e a duracao; o resto dos argumentos e o mesmo do teste em grupo

const MOVES: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right"]
const LOOKS: Array[StringName] = [&"look_left", &"look_right"]
const HELD: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right", &"look_left", &"look_right", &"run", &"attack"]
const IDLE_CHANCE := 0.15
const RUN_CHANCE := 0.4
const ATTACK_CHANCE := 0.3
const SECONDARY_CHANCE := 0.05
const DECISION_INTERVAL := 0.3

var role := ""
var players := 4
var minutes := 10.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	minutes = maxf(_arg("--minutos=").to_float(), 1.0)
	total_timeout = minutes * 60.0 + 300.0


func run() -> void:
	role = _arg("--role=")
	players = maxi(_arg("--players=").to_int(), 2)
	label = "carga-%s" % _arg("--name=").to_lower()
	_rng.seed = hash(label)
	play_with_gamepad()
	if role == "host" and await wait_until(func() -> bool: return not Net.room_code.is_empty(), "sala online criada"):
		print("E2E sala %s" % Net.room_code)
	if not await wait_scene("MissionIntro"):
		return
	await skip_cutscene()
	var deadline := Time.get_ticks_msec() + minutes * 60000.0
	while Time.get_ticks_msec() < deadline and failures.is_empty():
		await _play_a_moment()
	_release_all()
	check(failures.is_empty(), "jogou %d minutos e chegou na tentativa %d" % [minutes, RunState.attempt])
	await _leave_together()


# um trecho de 1 a 3 s: espera a fase, vota se o grupo caiu, fica parado ou anda lutando
func _play_a_moment() -> void:
	if not _in_level():
		_release_all()
		await wait_level()
		return
	var death := get_tree().current_scene.get_node("DeathScreen") as DeathScreen
	if death.visible:
		_release_all()
		if death.get_node("%ReviveButton").is_visible_in_tree():
			await vote_for_first_blessing()
		await get_tree().create_timer(1.0).timeout
		return
	var seconds := _rng.randf_range(1.0, 3.0)
	_release_all()
	if _rng.randf() < IDLE_CHANCE:
		await get_tree().create_timer(seconds).timeout
		return
	_hold(MOVES[_rng.randi() % MOVES.size()])
	if _rng.randf() < RUN_CHANCE:
		_hold(&"run")
	_hold(LOOKS[_rng.randi() % LOOKS.size()])
	await _fight_for(seconds)


func _fight_for(seconds: float) -> void:
	var end := Time.get_ticks_msec() + seconds * 1000.0
	while Time.get_ticks_msec() < end and _in_level():
		var roll := _rng.randf()
		if roll < ATTACK_CHANCE:
			_hold(&"attack")
		elif roll < ATTACK_CHANCE + SECONDARY_CHANCE:
			_tap(&"secondary")
		else:
			_send(&"attack", false)
		await get_tree().create_timer(DECISION_INTERVAL).timeout


func _in_level() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.is_node_ready() and scene.has_node("GameSession") and not Net.waiting_for_peers


func _hold(action: StringName) -> void:
	_send(action, true)


func _tap(action: StringName) -> void:
	_send(action, true)
	_send(action, false)


func _release_all() -> void:
	for action in HELD:
		_send(action, false)


func _send(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


# os clientes avisam que terminaram e so fecham depois que o host libera
func _leave_together() -> void:
	if role == "client":
		mark("fim")
		if await wait_mark("pode sair"):
			Net.leave()
	elif await wait_mark("fim", players - 1):
		mark("pode sair")
		await wait_until(func() -> bool: return multiplayer.get_peers().is_empty(), "clientes sairem")


func _arg(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return ""
