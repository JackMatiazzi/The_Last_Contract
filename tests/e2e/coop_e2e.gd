extends "res://tests/e2e/e2e_driver.gd"

# uma partida em grupo com processos de verdade ligados pela rede. Cada processo roda este mesmo
# roteiro com --role=host ou --role=client e --players=N; o lobby e preenchido pela linha de comando.
# O cliente de menor id ajuda o host (pedido forjado, reviver); os outros acompanham e conferem

const HOST_PEER := 1
const POTION := preload("res://resources/items/health_potion.tres")

var role := ""
var players := 2


func run() -> void:
	role = _arg("--role=")
	players = maxi(_arg("--players=").to_int(), 2)
	label = "coop-%s" % _arg("--name=").to_lower()
	play_with_gamepad()
	if role == "host" and await wait_until(func() -> bool: return Net.is_online(), "host abrir a porta"):
		print("E2E host escutando")
	# pela sala online os clientes so entram com o codigo, que o script de teste le daqui
	if role == "host" and "--host=relay" in OS.get_cmdline_user_args() and await wait_until(func() -> bool: return not Net.room_code.is_empty(), "sala online criada"):
		print("E2E sala %s" % Net.room_code)
	if not await wait_scene("MissionIntro"):
		return
	check(_allies_in_cutscene() == players - 1, "a cutscene mostra os %d aliados" % (players - 1))
	await skip_cutscene()

	if not await wait_level():
		return
	calm_enemies()
	var game := session()
	check(game.players.size() == players, "os %d aventureiros estao na fase" % players)
	check(Net.player_count == players, "a partida conta %d jogadores" % players)
	var host := Adventurer.of_peer(get_tree(), HOST_PEER)
	var helper := Adventurer.of_peer(get_tree(), _helper_peer())
	var guests := game.players.filter(func(adventurer: Adventurer) -> bool: return adventurer != host)
	check(host.get_display_name() == "Host" and guests.all(func(guest: Adventurer) -> bool: return guest.get_display_name().begins_with("Cliente")), "nomes do lobby sobre os bonecos")

	await _damage_crosses_the_network(host, helper)
	await _forged_damage_is_ignored()
	await _revive_through_the_network(host, helper)
	await _everyone_falls_and_votes()
	await _host_takes_everyone_down_the_trapdoor()
	await _michio_joins_and_the_room_holds()
	await _report_to_the_online_room()
	await _leave_together()


# pela sala online cada jogador manda o relatorio da partida com a ficha que recebeu; a sala precisa aceitar
func _report_to_the_online_room() -> void:
	if Net.relay_ticket.is_empty():
		return
	var answer := []
	Net.match_report_sent.connect(func(accepted: bool) -> void: answer.append(accepted), CONNECT_ONE_SHOT)
	if Playtest.is_running() and Playtest.uplink.is_active():
		# o caminho de verdade: o fim do contrato monta o resumo e manda pela fila do playtest
		Playtest.finish("left_party")
	else:
		var deaths: int = RunState.stats_of(multiplayer.get_unique_id()).deaths
		Net.send_match_report({"classe": RunState.current_adventurer().title, "resultado": "left_party", "tentativas": RunState.attempt, "mortes": deaths, "minutos": 1.0, "eventos": []})
	if await wait_until(func() -> bool: return not answer.is_empty(), "resposta da sala ao relatorio"):
		check(answer[0], "relatorio da partida aceito pela sala online")


func _damage_crosses_the_network(host: Adventurer, helper: Adventurer) -> void:
	if role == "host":
		helper.take_damage(2.0, host)
	var hurt := helper.get_max_health() - 2.0
	if await wait_until(func() -> bool: return is_equal_approx(helper.health, hurt), "dano do host no cliente"):
		check(true, "golpe de um jogador chega em todas as maquinas")


# o ajudante manda um pedido de dano forjado; quando o marco chega ao host, ele ja foi processado
func _forged_damage_is_ignored() -> void:
	var enemy := get_tree().current_scene.find_children("*", "Enemy", true, false)[0] as Enemy
	if _is_helper():
		enemy._request_damage.rpc_id(HOST_PEER, 5.0, NodePath())
		mark("forjado")
		await wait_mark("conferido")
	elif role == "host":
		await wait_mark("forjado")
		mark("conferido")
	else:
		await wait_mark("conferido")
	check(is_equal_approx(enemy.health, enemy.get_max_health()), "dano forjado e ignorado pelo host")


func _revive_through_the_network(host: Adventurer, helper: Adventurer) -> void:
	if role == "host":
		host.take_damage(999.0)
	if not await wait_until(func() -> bool: return host.is_dead, "host caido"):
		return
	if _is_helper():
		helper.global_position = host.global_position + Vector3(1.0, 0.0, 0.0)
		helper.inventory.add(POTION)
		if not await wait_until(func() -> bool: return helper.revive_target == host, "aviso de reviver"):
			return
		# a posicao nova ainda precisa chegar no host, que confere o alcance
		await wait_physics(10)
		press_action(&"interact")
	if await wait_until(func() -> bool: return not host.is_dead, "host revivido"):
		check(true, "aliado revivido pela rede")
	# quem gasta a pocao e a maquina do caido, num aviso que pode chegar depois do reviver
	if _is_helper() and await wait_until(func() -> bool: return helper.inventory.count_of(POTION) == 0, "pocao gasta"):
		check(true, "a pocao de quem reviveu foi gasta")
	# ninguem cai de novo antes de todos verem o reviver; senao as duas noticias chegam juntas
	mark("revivido")
	await wait_mark("revivido", players - 1)


func _everyone_falls_and_votes() -> void:
	session().player.take_damage(999.0)
	await vote_for_first_blessing()
	if not await wait_until(func() -> bool: return RunState.attempt == 2, "segunda tentativa"):
		return
	if not await wait_level():
		return
	check(session().players.size() == players, "o grupo volta inteiro na tentativa 2")
	check(RunState.stats_of(HOST_PEER).deaths == 2, "placar: host caiu duas vezes")
	var clients := Net.peers_in_order().filter(func(peer_id: int) -> bool: return peer_id != HOST_PEER)
	check(clients.all(func(peer_id: int) -> bool: return RunState.stats_of(peer_id).deaths == 1), "placar: cada cliente caiu uma vez")


# o host aperta E no alçapão e o grupo inteiro tem que chegar junto ao calabouço
func _host_takes_everyone_down_the_trapdoor() -> void:
	calm_enemies()
	mark("pronto para descer")
	if role == "host":
		if not await wait_mark("pronto para descer", players - 1):
			return
		var game := session()
		game.open_trapdoor_at(game.player.global_position + Vector3(1.5, 0, 0))
		if not await wait_until(func() -> bool: return game.player.interactables_in_reach > 0, "aviso do alçapão ao chegar perto"):
			return
		press_action(&"interact")
	if not await wait_scene("CalaboucoEscondidoLevel"):
		return
	if not await wait_until(func() -> bool: return not Net.waiting_for_peers and get_tree().current_scene.has_node("GameSession"), "calabouço carregado em todas as máquinas"):
		return
	check(session().players.size() == players, "o grupo inteiro desce pelo alçapão")


# no teste do grupo a partida caiu para todos logo depois de aceitar o Michio no grupo
func _michio_joins_and_the_room_holds() -> void:
	var found := get_tree().current_scene.find_children("*", "FriendlyUndead", true, false)
	check(not found.is_empty(), "o Michio está no calabouço")
	if found.is_empty():
		return
	var michio := found.front() as FriendlyUndead
	if role == "host":
		michio._net_invite.rpc()
	if not await wait_until(func() -> bool: return michio.awaiting_answer, "convite do Michio chegar"):
		return
	# o host só aceita depois de ver o jogador perto, e a posição demora a chegar numa máquina lenta
	if _is_helper():
		for attempt in 20:
			if michio.is_companion:
				break
			session().player.global_position = michio.global_position + Vector3(1.5, 0.3, 0)
			await wait_physics(10)
			michio._request_answer.rpc_id(HOST_PEER, true)
			await get_tree().create_timer(0.5).timeout
	if not await wait_until(func() -> bool: return michio.is_companion, "o Michio entrar no grupo"):
		return
	await get_tree().create_timer(20.0).timeout
	if role == "host":
		check(multiplayer.get_peers().size() == players - 1, "a sala continua com todos depois do Michio entrar")
	check(Net.is_online() and get_tree().current_scene.has_node("GameSession"), "todos seguem na partida 20 s depois do Michio entrar")


# os clientes avisam que terminaram e so fecham depois que o host libera
func _leave_together() -> void:
	if role == "client":
		mark("fim")
		if await wait_mark("pode sair"):
			Net.leave()
	elif await wait_mark("fim", players - 1):
		mark("pode sair")
		await wait_until(func() -> bool: return multiplayer.get_peers().is_empty(), "clientes sairem")


func _helper_peer() -> int:
	return Net.peers_in_order().filter(func(peer_id: int) -> bool: return peer_id != HOST_PEER).front()


func _is_helper() -> bool:
	return multiplayer.get_unique_id() == _helper_peer()


func _allies_in_cutscene() -> int:
	var count := 0
	for spot: Marker3D in get_tree().current_scene.party_spots:
		count += spot.get_child_count()
	return count


func _arg(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return ""
