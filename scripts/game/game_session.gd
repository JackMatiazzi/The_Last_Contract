class_name GameSession
extends Node
## Controlador do ciclo de vida da partida (Game Loop Principal).
## Gerencia a criação dos jogadores, fluxo de objetivos, invocação do chefe,
## captura/liberação do cursor do mouse, votação de bênçãos em caso de derrota e re-inicialização de tentativas.

const EXECUTION := "res://scenes/cutscenes/execution.tscn"
const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
## Fase bônus: o alçapão que o Necromante deixa ao morrer leva até ela.
const BONUS_LEVEL := "res://scenes/levels/calabouco_escondido_level.tscn"
const TRAPDOOR := preload("res://scenes/world/trapdoor.tscn")
## Segundos que o alçapão fica aberto. Se ninguém descer, o contrato fecha com a tela de vitória.
const TRAPDOOR_TIME := 30.0
const PLAYER_SPACING := 1.5
## golpes guardados no evento de morte: mostram no painel como a morte aconteceu
const HITS_ON_DEATH := 4
const STAGE_NAMES := {
	"res://scenes/levels/pedraalta_level.tscn": "Pedra Alta",
	"res://scenes/levels/calabouco_escondido_level.tscn": "Calabouço",
	"res://scenes/levels/village_level.tscn": "Vila",
}

## so nas cenas de teste; com encounters o ponto e sorteado
@export var player_spawn: Marker3D
@export var encounters: EncounterSpawner
@export var pause_menu: PauseMenu
@export var death_screen: DeathScreen
@export var hud: Hud
@export var boss_scene: PackedScene
@export var victory_screen: VictoryScreen

## o jogador desta maquina; em grupo os outros ficam em players
var player: Adventurer
var players: Array[Adventurer] = []
var boss: Enemy
var _groups_left := 0
var _groups_total := 0
# peer_id -> indice da bencao votada; so o host conta
var _votes := {}
var _vote_paths := PackedStringArray()
var _vote_open := false
var _contract_ended := false
var trapdoor_time := TRAPDOOR_TIME
var _trapdoor: Trapdoor
var _trapdoor_left := 0.0


func _ready() -> void:
	assert((player_spawn or encounters) and pause_menu and death_screen and hud, "GameSession: aponte spawn, pausa, tela de morte e HUD")
	_spawn_players()
	# Conexão de sinais dos componentes de jogo e UI
	player.died.connect(release_cursor)
	player.revived.connect(_on_player_revived)
	pause_menu.resumed.connect(_on_resumed)
	pause_menu.abandon_confirmed.connect(_abandon)
	death_screen.gave_up.connect(_give_up)
	death_screen.revive_chosen.connect(_cast_vote)
	if victory_screen:
		victory_screen.back_to_menu.connect(_back_to_menu)
	Net.player_left.connect(_on_player_left)
	player.died.connect(_log_death)
	capture_cursor()
	Net.report_level_loaded()
	if RunState.attempt == 1:
		hud.show_start_hint()
	_log_attempt()


## Nome da fase para o playtest e o painel: o nome legível quando a fase é conhecida, senão o nó raiz.
func stage_name() -> String:
	return STAGE_NAMES.get(get_parent().scene_file_path, get_parent().name)


func _log_attempt() -> void:
	if RunState.attempt == 1 and not Playtest.is_running():
		Playtest.start_run(_adventurer_of(multiplayer.get_unique_id()).title, players.size(), get_parent().name)
	Playtest.record("attempt_started", {"buffs": Array(RunState.buff_lines())})
	if get_parent().scene_file_path == BONUS_LEVEL:
		Playtest.record("dungeon_entered", {"stage": stage_name()})


func _log_death() -> void:
	var details := {"position": Playtest.position_of(player), "recap": player.damage_recap(), "enemy": player.damage_log.death_cause(), "stage": stage_name(), "hits": player.damage_log.last_hits(HITS_ON_DEATH)}
	Playtest.record("player_died", details.merged(player.damage_log.totals()))


func _unhandled_input(event: InputEvent) -> void:
	# Impede interações de jogo se o jogador estiver morto ou menus estiverem abertos
	if player.is_dead or pause_menu.visible or (victory_screen and victory_screen.visible):
		return
	if event.is_action_pressed("pause"):
		release_cursor()
		player.input_locked = true
		pause_menu.open(hud.objective_summary(), player)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# o clique que devolve o controle da camera nao deve virar ataque
		capture_cursor()
		get_viewport().set_input_as_handled()


# todas as maquinas usam a mesma semente: o sorteio de ponto e grupos sai igual;
# semente 0 e a cena aberta direto no editor, que sorteia como sempre
func _spawn_players() -> void:
	if Net.match_seed != 0:
		seed(Net.match_seed)
	var spawn := encounters.pick_player_spot() if encounters else player_spawn
	var peers := _peers_in_match()
	for i in peers.size():
		var peer_id := peers[i]
		var adventurer := _adventurer_of(peer_id).scene.instantiate() as Adventurer
		adventurer.name = str(peer_id) if Net.is_online() else "Player"
		adventurer.set_multiplayer_authority(peer_id)
		adventurer.position = spawn.global_position + Vector3.RIGHT * (i - (peers.size() - 1) / 2.0) * PLAYER_SPACING
		add_child(adventurer)
		adventurer.set_display_name(Net.display_name(peer_id))
		players.append(adventurer)
		adventurer.died.connect(_on_player_died)
		if peer_id == multiplayer.get_unique_id():
			player = adventurer
	player.camera.make_current()
	if encounters:
		_track_groups(encounters.spawn_groups(spawn.global_position))
	hud.bind(player)

## Retorna a lista de IDs de rede dos jogadores na partida.
func _peers_in_match() -> Array[int]:
	var peers: Array[int] = []
	if Net.is_online():
		peers.assign(Net.peers_in_order())
	else:
		peers.append(multiplayer.get_unique_id())
	return peers

## Retorna as informações da classe do aventureiro associado a um peer.
func _adventurer_of(peer_id: int) -> AdventurerInfo:
	if not Net.is_online():
		return RunState.current_adventurer()
	return RunState.roster()[Net.roster[peer_id]]

## Inicializa o rastreamento do progresso de eliminação dos grupos de inimigos.
func _track_groups(groups: Array[EnemyGroup]) -> void:
	_groups_left = groups.size()
	_groups_total = groups.size()
	for group in groups:
		group.cleared.connect(_on_group_cleared)
	_show_objective()

## Trata a conclusão da eliminação de um grupo de inimigos.
func _on_group_cleared() -> void:
	_groups_left -= 1
	_show_objective()
	Playtest.record("group_cleared", {"groups_left": _groups_left})
	if _groups_left == 0 and multiplayer.is_server():
		_summon_boss.rpc()

## Atualiza o texto do objetivo atual na HUD.
func _show_objective() -> void:
	hud.set_objective("Grupos restantes", _groups_left, _groups_total)

## RPC enviado pelo Host para instanciar o chefe final em todas as máquinas.
@rpc("authority", "call_local", "reliable")
func _summon_boss() -> void:
	if boss_scene == null or encounters.boss_spot == null:
		return
	boss = boss_scene.instantiate() as Enemy
	boss.name = "Boss"
	boss.position = encounters.to_local(encounters.boss_spot.global_position)
	boss.start_rising = true
	encounters.add_child(boss)
	boss.died.connect(_on_boss_died)
	hud.show_boss(boss)
	hud.set_objective("Derrote o Necromante")
	hud.announce_boss("O Necromante despertou na praça")
	Playtest.record("boss_summoned")

## com o grupo inteiro morto junto com ele não abre alçapão: vale a votação de bênção
func _on_boss_died() -> void:
	hud.set_objective("")
	Playtest.record("boss_killed")
	if multiplayer.is_server() and not _all_players_dead():
		open_trapdoor_at(boss.global_position)


func open_trapdoor_at(spot: Vector3) -> void:
	if multiplayer.is_server() and _trapdoor == null and not _contract_ended:
		_net_open_trapdoor.rpc(spot)


@rpc("authority", "call_local", "reliable")
func _net_open_trapdoor(spot: Vector3) -> void:
	if _trapdoor:
		return
	_trapdoor = TRAPDOOR.instantiate() as Trapdoor
	_trapdoor.session = self
	get_parent().add_child(_trapdoor)
	_trapdoor.global_position = spot
	_trapdoor_left = trapdoor_time
	hud.announce("O Necromante caiu e abriu um alçapão no chão")
	Playtest.record("trapdoor_opened")


func _process(delta: float) -> void:
	if _trapdoor == null or not _trapdoor.is_open:
		return
	_trapdoor_left = maxf(_trapdoor_left - delta, 0.0)
	hud.set_objective("Desça pelo alçapão: %d s" % ceili(_trapdoor_left))
	if _trapdoor_left == 0.0 and multiplayer.is_server():
		_net_close_trapdoor.rpc()


## tempo esgotado ou grupo morto depois do chefe: o contrato já foi cumprido
@rpc("authority", "call_local", "reliable")
func _net_close_trapdoor() -> void:
	if _trapdoor == null or not _trapdoor.is_open:
		return
	_trapdoor.close()
	_contract_ended = true
	hud.set_objective("")
	release_cursor()
	Playtest.record("trapdoor_expired")
	if victory_screen:
		victory_screen.open(RunState.attempt)
	Playtest.finish("victory")


## se todos caírem lá dentro, o grupo recomeça da entrada do calabouço, não da Pedra Alta
func descend_to_bonus() -> void:
	if multiplayer.is_server() and _trapdoor and _trapdoor.is_open:
		_net_descend.rpc()


@rpc("authority", "call_local", "reliable")
func _net_descend() -> void:
	_trapdoor.close()
	_contract_ended = true
	Playtest.record("trapdoor_entered")
	Net.waiting_for_peers = true
	get_tree().change_scene_to_file(BONUS_LEVEL)


# solo e um grupo de um: cai todo mundo, vota todo mundo
func _on_player_died() -> void:
	if not _all_players_dead():
		if player.is_dead:
			hud.announce("Você caiu. Seus aliados ainda lutam.")
		return
	_on_party_down()

## Executado quando todos os jogadores do grupo são derrotados.
func _on_party_down() -> void:
	release_cursor()
	if _trapdoor and _trapdoor.is_open:
		if multiplayer.is_server():
			_net_close_trapdoor.rpc()
		return
	if multiplayer.is_server() and not _vote_open:
		_start_vote()


# cada jogador vota numa das bencaos sorteadas pelo host; empate e sorteado
func _start_vote() -> void:
	var paths := PackedStringArray()
	for buff in RunState.roll_choices():
		paths.append(buff.resource_path)
	_net_open_vote.rpc(paths)

## RPC de autoridade que exibe a tela de morte e as opções de votação de bênçãos.
@rpc("authority", "call_local", "reliable")
func _net_open_vote(paths: PackedStringArray) -> void:
	_vote_open = true
	_votes.clear()
	_vote_paths = paths
	var choices: Array[Buff] = []
	for path in paths:
		var buff := buff_at(path)
		if buff:
			choices.append(buff)
	death_screen.set_recap(player.damage_recap())
	death_screen.open_vote(choices, multiplayer.is_server())

## Envia a escolha de bênção do jogador local para o Host.
func _cast_vote(buff: Buff) -> void:
	var index := _vote_paths.find(buff.resource_path) if buff else -1
	death_screen.hide()
	if Net.is_coop():
		hud.announce("Voto registrado. Aguardando o grupo.")
	if multiplayer.is_server():
		_register_vote(1, index)
	else:
		_net_vote.rpc_id(1, index)

## RPC recebido pelo Host contendo o voto de um cliente.
@rpc("any_peer", "reliable")
func _net_vote(index: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and _vote_open and Net.is_player(sender) and index >= -1 and index < _vote_paths.size():
		_register_vote(sender, index)

## Computa o voto de um jogador no Host e tenta encerrar a votação se todos votarem.
func _register_vote(peer_id: int, index: int) -> void:
	_votes[peer_id] = index
	_try_close_vote()

## Avalia se todos os jogadores ativos votaram. Se sim, contabiliza o vencedor e reinicia a fase.
func _try_close_vote() -> void:
	if not multiplayer.is_server() or _votes.is_empty() or _votes.size() < Net.player_count:
		return
	var winner: int = most_voted(_votes).pick_random()
	_votes.clear()
	_vote_open = false
	_net_restart.rpc(_vote_paths[winner] if winner >= 0 else "", randi())


## empatados voltam todos; quem chama sorteia entre eles
static func most_voted(votes: Dictionary) -> Array:
	var tally := {}
	for index: int in votes.values():
		tally[index] = tally.get(index, 0) + 1
	var best: int = tally.values().max()
	return tally.keys().filter(func(index: int) -> bool: return tally[index] == best)


## o caminho vem do host pela rede: so bencaos da pasta de bencaos
static func buff_at(path: String) -> Buff:
	if not path.begins_with(RunState.BUFF_DIR + "/") or not path.ends_with(".tres") or ".." in path:
		return null
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Buff

## Retorna true se todos os aventureiros da partida estiverem mortos.
func _all_players_dead() -> bool:
	return players.all(func(adventurer: Adventurer) -> bool: return adventurer.is_dead)

## Trata a saída de um jogador desconectado durante a sessão ativa.
func _on_player_left(peer_id: int) -> void:
	var adventurer := get_node_or_null(str(peer_id)) as Adventurer
	if adventurer == null:
		return
	players.erase(adventurer)
	adventurer.queue_free()
	hud.announce("Um aliado saiu da partida.")
	_votes.erase(peer_id)
	if _vote_open:
		_try_close_vote()
	elif _all_players_dead():
		_on_party_down()

## Callback de retomada de jogo através do menu de pausa.
func _on_resumed() -> void:
	player.input_locked = false
	capture_cursor()


# reviver com o menu aberto nao pode prender o cursor por baixo dele
func _on_player_revived() -> void:
	if not pause_menu.visible:
		capture_cursor()

## Reinicia as variáveis de progresso e retorna ao menu principal.
func _back_to_menu() -> void:
	Playtest.finish("back_to_menu")
	RunState.reset()
	get_tree().change_scene_to_file(MAIN_MENU)

## Prende e oculta o ponteiro do mouse na janela do jogo.
func capture_cursor() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Libera e exibe o ponteiro do mouse na janela do jogo.
func release_cursor() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## RPC enviado pelo Host ordenando a recarga da cena para a próxima tentativa.
@rpc("authority", "call_local", "reliable")
func _net_restart(buff_path: String, seed_value: int) -> void:
	var buff := buff_at(buff_path)
	Playtest.record("blessing_chosen", {"buff": buff.title if buff else ""})
	RunState.start_next_attempt(buff)
	Net.match_seed = seed_value
	Net.waiting_for_peers = true
	get_tree().reload_current_scene()


# em grupo, abandonar tira so quem saiu; se for o host, a partida acaba para todos
func _abandon() -> void:
	if Net.is_coop():
		Playtest.finish("left_party")
		Net.leave()
		_back_to_menu()
		return
	_execute()

## Solicita o acionamento da sequência de derrota/execução final.
func _give_up() -> void:
	_net_execute.rpc()

## RPC de autoridade para sincronizar o carregamento da cena de execução.
@rpc("authority", "call_local", "reliable")
func _net_execute() -> void:
	_execute()


## fim de fase sem boss (o calabouco): cumprido abre a vitoria; com morto-vivo de pe, o contrato falha
func end_contract(fulfilled: bool) -> void:
	if multiplayer.is_server() and not _contract_ended:
		_net_end_contract.rpc(fulfilled)


@rpc("authority", "call_local", "reliable")
func _net_end_contract(fulfilled: bool) -> void:
	_contract_ended = true
	Playtest.record("dungeon_exit", {"stage": stage_name()})
	if fulfilled:
		release_cursor()
		victory_screen.open(RunState.attempt)
		Playtest.finish("victory")
	else:
		Playtest.finish("contract_failed")
		_execute()

## Limpa o estado da corrida e transiciona para a cena de execução.
func _execute() -> void:
	Playtest.finish("executed")
	RunState.reset()
	get_tree().change_scene_to_file(EXECUTION)
