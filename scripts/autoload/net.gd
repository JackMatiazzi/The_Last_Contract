extends Node
## Gerenciador de rede e multiplayer (Autoload).
## Responsável por criar/entrar em salas (ENet ou WebSocket), gerenciar a lista de jogadores (roster),
## sincronizar nomes, validar caracteres, controlar a barra de carregamento do nível
## e intermediar mensagens RPC de estado de jogo.
# sem peer configurado o Godot usa OfflineMultiplayerPeer: o jogo solo e um host sem ninguem conectado

signal roster_changed
signal connection_failed
signal player_left(peer_id: int)
signal room_ready(code: String)
signal match_report_sent(accepted: bool)

## ENET e a rede local (UDP); RELAY e a sala online com codigo, a API no Cloudflare (the-last-contract-api);
## WEBSOCKET e o host publicando a propria porta com o tunel do cloudflared
enum Transport { ENET, WEBSOCKET, RELAY }

const PORT := 7777
## endereco da sala online (repositorio the-last-contract-api) depois do deploy; --relay=ws://... troca,
## para testar com a API rodando local
const RELAY_URL := "wss://the-last-contract-api.last-contract.workers.dev"
const ROOM_CODE_LETTERS := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const ROOM_CODE_LENGTH := 6
const WEB_SCHEMES := {"https://": "wss://", "http://": "ws://", "wss://": "wss://", "ws://": "ws://"}
const WEB_BIND_ADDRESS := "127.0.0.1"
const WEB_MAX_QUEUED_PACKETS := 512
const WEB_HANDSHAKE_TIMEOUT := 3.0
const MAX_PLAYERS := 4
const MISSION_INTRO := "res://scenes/cutscenes/mission_intro.tscn"
const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const NO_CHOICE := -1
const MAX_NAME_LENGTH := 16
## o placar de grupos guarda ate 24 caracteres (igual a API)
const MAX_GROUP_NAME_LENGTH := 24
const VIRTUAL_ADAPTERS := ["virtualbox", "vmware", "hyper-v", "vethernet", "wsl", "docker", "loopback"]
## invisiveis ou que invertem a direcao do texto: um nome com eles baguncaria placar e avisos
const HIDDEN_CHARACTERS := [
	[0x7F, 0x9F], [0xAD, 0xAD], [0x61C, 0x61C], [0x115F, 0x1160], [0x180E, 0x180E], [0x200B, 0x200F],
	[0x2028, 0x202E], [0x2060, 0x206F], [0x2800, 0x2800], [0x3164, 0x3164], [0xFE00, 0xFE0F],
	[0xFEFF, 0xFEFF], [0xFFA0, 0xFFA0], [0xE0000, 0xE007F],
]

## peer_id -> indice em RunState.ADVENTURERS
var roster := {}
## peer_id -> nome escolhido no lobby
var names := {}
var friendly_fire := true
## nome do grupo escolhido no lobby (opcional); vai no relatorio para o placar de grupos
var group_name := ""
var match_seed := 0
## depois do inicio ninguem troca de aventureiro nem de nome
var in_match := false
var last_error := ""
var relay_url := RELAY_URL
## codigo da sala online que o host passa para os amigos
var room_code := ""
## ficha que a sala online deu a este jogador; o relatorio do fim da partida so vale com ela, uma vez
var relay_ticket := ""
## solo (offline ou host sozinho) conta 1: reviver aliado, votacao e pausa sem congelar ficam desligados
var player_count: int:
	get:
		return maxi(roster.size(), 1) if is_online() else 1
# --host / --join=IP / --adventurer=N / --autostart=N, para testar varias instancias pelo editor
var _command_line := Array(OS.get_cmdline_user_args())
## entre a troca de fase e a barreira ninguem transmite: o estado inicial sai igual em todas as maquinas
var waiting_for_peers := false
# so o host conta quem ja terminou de carregar a fase atual
var _loaded_peers: Array[int] = []


func _ready() -> void:
	# Conecta os sinais nativos do sistema Multiplayer da Godot
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	for arg: String in _command_line:
		if arg.begins_with("--relay="):
			relay_url = arg.trim_prefix("--relay=")


func is_online() -> bool:
	return not multiplayer.multiplayer_peer is OfflineMultiplayerPeer


func is_coop() -> bool:
	return player_count > 1

## Abre a sala na porta. Em WEBSOCKET os outros entram pelo endereco do tunel (wss://).
func host(port := PORT, transport := Transport.ENET) -> Error:
	var peer: MultiplayerPeer
	var error: Error
	if transport == Transport.RELAY:
		var relay_peer := RelayPeer.new()
		relay_peer.room_ready.connect(_on_room_ready)
		relay_peer.room_ready.connect(_remember_ticket.bind(relay_peer))
		# adiado: o aviso sai de dentro do poll do proprio peer, que nao pode ser trocado ali
		relay_peer.dropped.connect(_on_relay_host_dropped.bind(relay_peer), CONNECT_DEFERRED)
		error = relay_peer.create_host(relay_url)
		peer = relay_peer
	elif transport == Transport.WEBSOCKET:
		# so o tunel enxerga a porta: na rede local quem quiser entrar sem o link nao consegue
		var web_peer := WebSocketMultiplayerPeer.new()
		web_peer.max_queued_packets = WEB_MAX_QUEUED_PACKETS
		web_peer.handshake_timeout = WEB_HANDSHAKE_TIMEOUT
		error = web_peer.create_server(port, WEB_BIND_ADDRESS)
		peer = web_peer
	else:
		var enet_peer := ENetMultiplayerPeer.new()
		error = enet_peer.create_server(port, MAX_PLAYERS - 1)
		peer = enet_peer
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	roster = {1: NO_CHOICE}
	names = {1: Settings.player_name}
	roster_changed.emit()
	return OK

## Entra na sala: codigo de 6 letras vai pela sala online, link do tunel (https/wss) por WebSocket,
## IP ou nome da maquina por ENet.
func join(address: String, port := PORT) -> Error:
	var web := web_address(address)
	var peer: MultiplayerPeer
	var error: Error
	if is_room_code(address):
		var relay_peer := RelayPeer.new()
		relay_peer.room_ready.connect(_remember_ticket.bind(relay_peer))
		error = relay_peer.create_client(relay_url, address.strip_edges().to_upper())
		peer = relay_peer
	elif not web.is_empty():
		var web_peer := WebSocketMultiplayerPeer.new()
		error = web_peer.create_client(web)
		peer = web_peer
	else:
		var enet_peer := ENetMultiplayerPeer.new()
		error = enet_peer.create_client(address.strip_edges(), port)
		peer = enet_peer
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	return OK


## o cloudflared mostra um link https://; para o jogo ele vira wss://. Vazio quando nao e endereco web
static func web_address(raw: String) -> String:
	var address := raw.strip_edges().trim_suffix("/")
	for scheme: String in WEB_SCHEMES:
		if address.to_lower().begins_with(scheme):
			return WEB_SCHEMES[scheme] + address.substr(scheme.length())
	return ""


static func is_room_code(raw: String) -> bool:
	var code := raw.strip_edges().to_upper()
	return code.length() == ROOM_CODE_LENGTH and Array(code.split("")).all(func(letter: String) -> bool: return letter in ROOM_CODE_LETTERS)


func _remember_ticket(_code: String, relay_peer: RelayPeer) -> void:
	relay_ticket = relay_peer.ticket


## endereço HTTP de uma rota da API da sala online (relatório, playtest, apagar dados)
func api_url(path: String) -> String:
	return http_address(relay_url) + path


static func http_address(web_url: String) -> String:
	if web_url.begins_with("wss://"):
		return "https://" + web_url.trim_prefix("wss://")
	return "http://" + web_url.trim_prefix("ws://") if web_url.begins_with("ws://") else web_url


## relatorio do fim da partida para o banco da sala online (placar e playtest). Sem ficha nao manda:
## partida local ou pelo tunel nao passa pela sala. A ficha vale uma vez so
func send_match_report(report: Dictionary) -> Error:
	var full := take_match_report(report)
	if full.is_empty():
		return ERR_UNCONFIGURED
	var body := JSON.stringify(full)
	var request := HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_report_sent.bind(request))
	return request.request(http_address(relay_url) + "/telemetria", ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)


## junta a ficha e o apelido ao relatório e gasta a ficha; vazio quando a partida não passou pela sala
func take_match_report(report: Dictionary) -> Dictionary:
	if relay_ticket.is_empty():
		return {}
	var full := report.merged({"ficha": relay_ticket, "apelido": Settings.player_name})
	relay_ticket = ""
	return full


func _on_report_sent(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, request: HTTPRequest) -> void:
	var accepted := result == HTTPRequest.RESULT_SUCCESS and code == 200
	if not accepted:
		push_warning("Net: relatorio da partida nao foi aceito pela sala online (resultado %d, http %d)" % [result, code])
	request.queue_free()
	match_report_sent.emit(accepted)


func _on_room_ready(code: String) -> void:
	room_code = code
	_share_roster()
	room_ready.emit(code)


# sem internet, sala expirada ou relay fora do ar: no lobby volta a tela de conexao, na partida vai ao menu
## o aviso chega adiado: se o host ja saiu e abriu outra sala, ele e de uma conexao velha
func _on_relay_host_dropped(relay_peer: RelayPeer) -> void:
	if multiplayer.multiplayer_peer != relay_peer:
		return
	last_error = _relay_refusal("A conexão com a sala online caiu.")
	log_network("conexão com a sala caiu na partida=%s: %s" % [in_match, last_error])
	var was_in_match := in_match
	leave()
	if was_in_match:
		get_tree().paused = false
		get_tree().change_scene_to_file(MAIN_MENU)
	else:
		connection_failed.emit()


## o WebSocket nao tem limite de clientes como o ENet: o host recusa o quinto e quem chega no meio
func admits_new_player() -> bool:
	return not in_match and roster.size() < MAX_PLAYERS

## Encerra a conexão de rede e restaura o estado inicial do gerenciador de rede.
func leave() -> void:
	if is_online():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	roster.clear()
	names.clear()
	_loaded_peers.clear()
	waiting_for_peers = false
	friendly_fire = true
	group_name = ""
	in_match = false
	room_code = ""

## Solicita a seleção de um aventureiro. Se for o cliente, envia RPC para o servidor.
func choose_adventurer(index: int) -> void:
	if multiplayer.is_server():
		_apply_choice(1, index)
	else:
		_request_choice.rpc_id(1, index)

## Retorna o nome formatado de um peer_id específico.
func display_name(peer_id: int) -> String:
	return names.get(peer_id, Settings.player_name)

## Limpa e valida o nome do jogador, retornando o nome padrão caso o resultado fique vazio.
static func clean_name(raw: String) -> String:
	var cleaned := clean_text(raw, MAX_NAME_LENGTH)
	return cleaned if not cleaned.is_empty() else Settings.DEFAULT_PLAYER_NAME


## texto vindo de outro jogador: sem quebra de linha, caractere de controle ou invisivel
static func clean_text(raw: String, max_length: int) -> String:
	var kept := PackedStringArray()
	for character in raw:
		if _is_visible_character(character.unicode_at(0)):
			kept.append(character)
	return "".join(kept).strip_edges().left(max_length)

## Verifica se um código Unicode de caractere é visível e válido.
static func _is_visible_character(code: int) -> bool:
	if code < 32:
		return false
	return not HIDDEN_CHARACTERS.any(func(span: Array) -> bool: return code >= span[0] and code <= span[1])


## enderecos que outro jogador consegue usar: rede local e VPN de jogo (Tailscale, Radmin);
## placas de maquina virtual ficam de fora porque ninguem de fora alcanca
static func shareable_addresses() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for interface in IP.get_local_interfaces():
		var label: String = interface.friendly
		if VIRTUAL_ADAPTERS.any(func(word: String) -> bool: return word in label.to_lower()):
			continue
		for address: String in interface.addresses:
			if address.count(".") == 3 and not address.begins_with("127.") and not address.begins_with("169.254."):
				found.append({"address": address, "label": label})
	return found


func is_player(peer_id: int) -> bool:
	return roster.has(peer_id)

## Atualiza o nome do jogador local e sincroniza na rede se estiver online.
func set_player_name(raw: String) -> void:
	var cleaned := clean_name(raw)
	Settings.set_value(&"player_name", cleaned)
	if not is_online():
		return
	if multiplayer.is_server():
		names[1] = cleaned
		_share_roster()
	else:
		_request_name.rpc_id(1, cleaned)

## so o host define; vazio e permitido (o placar mostra os nomes dos jogadores)
func set_group_name(raw: String) -> void:
	if multiplayer.is_server():
		group_name = clean_text(raw, MAX_GROUP_NAME_LENGTH)
		_share_roster()


## Define e sincroniza o estado do fogo amigo (somente o Host).
func set_friendly_fire(enabled: bool) -> void:
	if multiplayer.is_server():
		friendly_fire = enabled
		_share_roster()

## Verifica se o índice de um aventureiro já foi escolhido por outro jogador.
func is_taken(index: int) -> bool:
	for peer_id in roster:
		if peer_id != multiplayer.get_unique_id() and roster[peer_id] == index:
			return true
	return false

## Verifica se a partida pode ser iniciada (apenas o Host pode iniciar e todos devem ter escolhido personagem).
func can_start() -> bool:
	return multiplayer.is_server() and not roster.is_empty() and not roster.values().has(NO_CHOICE)

## Inicia a partida fechando novas conexões e enviando a semente de jogo para os clientes.
func start_match() -> void:
	if not can_start():
		return
	multiplayer.multiplayer_peer.refuse_new_connections = true
	_start.rpc(randi())

## Verifica se existem argumentos de linha de comando para autostart/host/join.
func has_command_line() -> bool:
	return _command_line.any(func(arg: String) -> bool: return arg.begins_with("--host") or arg.begins_with("--join"))


## consumida uma vez so: voltar ao menu nao reconecta sozinho
func take_command_line() -> Array:
	var args := _command_line
	_command_line = []
	return args


## o host so comeca a mandar estado depois que todas as maquinas tem os mesmos nos
func report_level_loaded() -> void:
	if not is_coop():
		waiting_for_peers = false
		return
	get_tree().paused = true
	if multiplayer.is_server():
		_register_loaded(1)
	else:
		_net_level_loaded.rpc_id(1, match_seed)

## RPC enviado pelos clientes ao servidor confirmando o carregamento da fase.
@rpc("any_peer", "reliable")
func _net_level_loaded(seed_value: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and seed_value == match_seed and is_player(sender):
		_register_loaded(sender)

## Registra um peer como carregado no Servidor.
func _register_loaded(peer_id: int) -> void:
	if peer_id not in _loaded_peers:
		_loaded_peers.append(peer_id)
	_release_when_everyone_loaded()

## Quando todos os jogadores carregam a fase, despacha a liberação geral do jogo.
func _release_when_everyone_loaded() -> void:
	if not _loaded_peers.has(1) or _loaded_peers.size() < player_count:
		return
	_loaded_peers.clear()
	_net_everyone_loaded.rpc()

## RPC enviado pelo servidor para despausar o jogo em todos os clientes simultaneamente.
@rpc("authority", "call_local", "reliable")
func _net_everyone_loaded() -> void:
	log_network("todos carregaram %s" % get_tree().current_scene.name)
	waiting_for_peers = false
	get_tree().paused = false

## Retorna uma lista ordenada dos IDs dos jogadores conectados.
func peers_in_order() -> Array:
	var ids := roster.keys()
	ids.sort()
	return ids

## RPC recebido pelo servidor solicitando alteração de nome de um cliente.
@rpc("any_peer", "reliable")
func _request_name(raw: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	var cleaned := clean_name(raw)
	if multiplayer.is_server() and not in_match and is_player(sender) and names.get(sender) != cleaned:
		names[sender] = cleaned
		_share_roster()

## RPC recebido pelo servidor solicitando escolha de personagem.
@rpc("any_peer", "reliable")
func _request_choice(index: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and not in_match and is_player(sender) and index >= 0 and index < RunState.ADVENTURERS.size():
		_apply_choice(sender, index)

## Processa a escolha de aventureiro de um peer e sincroniza com o grupo.
func _apply_choice(peer_id: int, index: int) -> void:
	for other in roster:
		if other != peer_id and roster[other] == index:
			return
	roster[peer_id] = index
	_share_roster()

## Sincroniza a lista inteira de jogadores e configurações do lobby para todos os clientes.
## a sala online so aceita mensagens depois de responder; ate la a lista fica so aqui
func _share_roster() -> void:
	if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_sync_roster.rpc(roster, names, friendly_fire, group_name)
	roster_changed.emit()

## RPC de autoridade que substitui o estado do lobby local pelos dados atualizados do host.
## O host tambem e outro jogador: grupo maior que o limite e ignorado e os nomes sao limpos de novo
@rpc("authority", "reliable")
func _sync_roster(shared: Dictionary, shared_names: Dictionary, shared_friendly_fire: bool, shared_group_name := "") -> void:
	if shared.size() > MAX_PLAYERS or shared_names.size() > MAX_PLAYERS or not shared.keys().all(_is_roster_entry.bind(shared)):
		return
	roster = shared
	names = {}
	for peer_id: Variant in shared_names:
		names[peer_id] = clean_name(str(shared_names[peer_id]))
	friendly_fire = shared_friendly_fire
	group_name = clean_text(shared_group_name, MAX_GROUP_NAME_LENGTH)
	roster_changed.emit()


static func _is_roster_entry(peer_id: Variant, shared: Dictionary) -> bool:
	var choice: Variant = shared[peer_id]
	return peer_id is int and choice is int and choice >= NO_CHOICE and choice < RunState.ADVENTURERS.size()

## RPC enviado pelo Host para iniciar a transição de cena e o loop da partida.
@rpc("authority", "call_local", "reliable")
func _start(seed_value: int) -> void:
	match_seed = seed_value
	waiting_for_peers = true
	in_match = true
	_loaded_peers.clear()
	RunState.reset()
	RunState.adventurer = RunState.roster()[roster[multiplayer.get_unique_id()]]
	get_tree().change_scene_to_file(MISSION_INTRO)

## Callback executado no Host quando um novo cliente se conecta.
func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not admits_new_player():
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return
	roster[peer_id] = NO_CHOICE
	names[peer_id] = "Jogador %d" % roster.size()
	_share_roster()


# sai da lista antes de avisar: quem conta votos e prontos ja ve o grupo menor.
# Quem foi recusado na porta nunca entrou na lista e nao vira aviso
func _on_peer_disconnected(peer_id: int) -> void:
	if not roster.has(peer_id):
		return
	log_network("jogador %d (%s) saiu" % [peer_id, names.get(peer_id, "?")])
	roster.erase(peer_id)
	names.erase(peer_id)
	_loaded_peers.erase(peer_id)
	player_left.emit(peer_id)
	if multiplayer.is_server():
		_share_roster()
		_release_when_everyone_loaded()

# a sala online explica por que recusou ou fechou (cheia, codigo errado, versao velha); vale mais que o generico
func _relay_refusal(fallback: String) -> String:
	var relay_peer := multiplayer.multiplayer_peer as RelayPeer
	return relay_peer.refusal if relay_peer and not relay_peer.refusal.is_empty() else fallback

## Callback de falha ao tentar conectar em um servidor.
func _on_connection_failed() -> void:
	last_error = _relay_refusal("Não foi possível conectar ao host.")
	leave()
	connection_failed.emit()

## Callback executado quando o servidor fecha a sala ou cai.
## linha com horário no godot.log: a queda de uma partida em grupo fica registrada em qualquer máquina
func log_network(event: String) -> void:
	print("[rede %s] %s" % [Time.get_datetime_string_from_system(), event])


func _on_server_disconnected() -> void:
	log_network("o host desconectou: %s" % _relay_refusal("sem motivo"))
	# o host recusa sem explicar; quem nunca recebeu a lista foi barrado na porta
	var was_in_room := roster.has(multiplayer.get_unique_id())
	last_error = _relay_refusal("O host encerrou a partida." if was_in_room else "A sala está cheia ou a partida já começou.")
	leave()
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU)
