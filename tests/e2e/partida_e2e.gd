extends "res://tests/e2e/carga_e2e.gd"

# uma partida em grupo inteira pela sala online, do jeito que a turma joga: bots lutando de verdade na
# Pedra Alta, o Necromante com as levas, a descida pelo alçapão, o Michio entrando no grupo e mais luta no
# calabouço. O host derruba um grupo a cada tanto para a partida andar. Se a sala cair, o log diz quando e
# por quê (linhas "[rede ...]"). --boss=S e --calabouco=S ajustam quanto tempo cada luta dura

const CLEAR_EVERY := 10.0
const HOST_PEER := 1

var _boss_seconds := 60.0
var _dungeon_seconds := 180.0


func _init() -> void:
	super()
	_boss_seconds = _arg_or("--boss=", _boss_seconds)
	_dungeon_seconds = _arg_or("--calabouco=", _dungeon_seconds)
	# a Pedra Alta com um grupo a cada 10 s leva uns 3 min; o resto é a luta pedida, com folga para carregar
	total_timeout = 600.0 + _boss_seconds + _dungeon_seconds


func run() -> void:
	role = _arg("--role=")
	players = maxi(_arg("--players=").to_int(), 2)
	label = "partida-%s" % _arg("--name=").to_lower()
	_rng.seed = hash(label)
	play_with_gamepad()
	if role == "host" and await wait_until(func() -> bool: return not Net.room_code.is_empty(), "sala online criada"):
		print("E2E sala %s" % Net.room_code)
	if not await wait_scene("MissionIntro"):
		return
	await skip_cutscene()
	if not await wait_level():
		return
	Net.log_network("simulação: Pedra Alta")
	if not await _reach_the_dungeon():
		return
	Net.log_network("simulação: calabouço")
	await _michio_joins()
	await _play_for(_dungeon_seconds)
	_release_all()
	check(Net.is_online() and _in_level(), "a sala aguentou a partida inteira, do começo ao calabouço com o Michio")
	await _leave_together()


# um laço só, que se recupera se o grupo cair e a fase recomeçar: todos lutam; o host derruba um grupo a
# cada CLEAR_EVERY s, deixa o Necromante lutar por --boss s, mata ele e desce pelo alçapão
func _reach_the_dungeon() -> bool:
	var next_clear := Time.get_ticks_msec() + CLEAR_EVERY * 1000.0
	var boss_since := -1.0
	while failures.is_empty() and Net.is_online():
		var scene := get_tree().current_scene
		if scene and scene.name == "CalaboucoEscondidoLevel":
			return await wait_until(func() -> bool: return _in_level(), "calabouço carregado em todas as máquinas")
		if _in_level():
			_keep_alive()
			var game := session()
			var boss_up := game.boss != null and is_instance_valid(game.boss) and not game.boss.is_dead
			if boss_up and boss_since < 0.0:
				boss_since = Time.get_ticks_msec()
				Net.log_network("simulação: Necromante")
			elif not boss_up and game._trapdoor == null:
				boss_since = -1.0
			if role == "host":
				if game._trapdoor and game._trapdoor.is_open:
					game.descend_to_bonus()
				elif boss_up and Time.get_ticks_msec() - boss_since > _boss_seconds * 1000.0:
					game.boss.take_damage(9999.0, game.player)
				elif not boss_up and Time.get_ticks_msec() >= next_clear:
					_clear_one_group()
					next_clear = Time.get_ticks_msec() + CLEAR_EVERY * 1000.0
		await _play_a_moment()
	check(false, "a sala caiu antes do calabouço (veja as linhas [rede] do log)")
	return false


# cada um cura o próprio aventureiro: a simulação é da rede, não da dificuldade
func _keep_alive() -> void:
	var me := session().player
	if not me.is_dead:
		me.heal(me.get_max_health())


func _clear_one_group() -> void:
	var killer := session().player
	for group in get_tree().current_scene.find_children("*", "EnemyGroup", true, false):
		var alive := group.find_children("*", "Enemy", true, false).filter(func(enemy: Enemy) -> bool: return not enemy.is_dead)
		if alive.is_empty():
			continue
		for enemy: Enemy in alive:
			enemy.take_damage(999.0, killer)
		return
	# grupos limpos e elites ainda de pé fora deles
	for enemy: Enemy in get_tree().get_nodes_in_group(UndeadCensus.GROUP).filter(func(node: Node) -> bool: return node is Enemy and not node.is_dead and node != session().boss):
		enemy.take_damage(999.0, killer)


func _play_for(seconds: float) -> void:
	var end := Time.get_ticks_msec() + seconds * 1000.0
	while Time.get_ticks_msec() < end and failures.is_empty() and Net.is_online():
		if _in_level():
			_keep_alive()
		await _play_a_moment()
	if not Net.is_online():
		check(false, "a sala caiu durante a luta (veja as linhas [rede] do log)")


func _michio_joins() -> void:
	var found := get_tree().current_scene.find_children("*", "FriendlyUndead", true, false)
	if found.is_empty():
		check(false, "Michio no calabouço")
		return
	var michio := found.front() as FriendlyUndead
	if role == "host":
		michio._net_invite.rpc()
	if not await wait_until(func() -> bool: return michio.awaiting_answer or michio.is_companion, "convite do Michio"):
		return
	if multiplayer.get_unique_id() == _first_client():
		session().player.global_position = michio.global_position + Vector3(1.5, 0.3, 0)
		await wait_physics(10)
		michio._request_answer.rpc_id(HOST_PEER, true)
	if await wait_until(func() -> bool: return michio.is_companion, "o Michio entrar no grupo"):
		Net.log_network("simulação: Michio entrou no grupo")


func _first_client() -> int:
	return Net.peers_in_order().filter(func(peer_id: int) -> bool: return peer_id != HOST_PEER).front()


func _arg_or(prefix: String, fallback: float) -> float:
	var value := _arg(prefix)
	return value.to_float() if not value.is_empty() else fallback
