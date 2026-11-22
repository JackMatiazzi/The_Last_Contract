class_name RelayPeer
extends MultiplayerPeerExtension
## Peer de rede que passa pela sala no Cloudflare (repositorio the-last-contract-api). Os pacotes do Godot sao
## juntados e enviados em lotes de FLUSH_INTERVAL: o Cloudflare cobra por mensagem recebida, nao pelo
## tamanho, entao luta com muitos inimigos custa o mesmo que andar pela vila. A sala carimba quem
## mandou cada pacote; ninguem consegue se passar pelo host.
##
## Protocolo 2: cada lote leva o numero do primeiro pacote e confirma o que ja chegou da sala. Se a conexao
## cai ou fica muda, o jogo volta sozinho para a mesma sala e cada lado reenvia o que o outro nao recebeu;
## para o Godot e para os outros jogadores ninguem saiu.

signal room_ready(code: String)
## a conexao com a sala caiu sem o jogo pedir; o Godot so avisa isso para clientes, entao o host ouve aqui
signal dropped
## a conexao caiu e o jogo esta tentando voltar (true), ou voltou (false)
signal resuming(active: bool)
## outro jogador perdeu a conexao e a sala espera ele voltar (true), ou ele voltou (false)
signal peer_away(peer: int, away: bool)

const PROTOCOL_VERSION := "2"
const HOST_ID := 1
const MAX_ID := 0x7FFFFFFF
const FLUSH_INTERVAL_MSEC := 100
## par (int32) | canal (uint8) | modo (uint8) | tamanho (uint32); igual ao src/protocolo.js da API
const HEADER_SIZE := 10
## confirmado (uint32) | primeiro (uint32) na frente de cada lote; igual ao src/fluxo.js da API
const STREAM_HEADER_SIZE := 8
## a sala derruba mensagens acima de 64 KB; o lote sai antes de chegar perto disso
const MAX_BATCH_BYTES := 60000
## a sala recusa a mensagem com mais de 512 pacotes e derruba quem mandou: o lote sai antes de chegar lá,
## mesmo com muitos personagens mandando posição ao mesmo tempo
const MAX_BATCH_RECORDS := 400
## a sala derruba quem manda mais de 15 mensagens numa janela de 1 s; com um intervalo minimo entre envios,
## nem o reenvio depois de uma queda nem o atraso da rede juntam mais de 11 numa janela
const MIN_SEND_SPACING_MSEC := 100
const SOCKET_BUFFER_BYTES := 1 << 17
## o jogo consome a fila a cada quadro; fila desse tamanho so acontece com alguem inundando a sala
const MAX_INCOMING := 4096
const ROOM_CLOSE_CODES := 4000
## a sala responde "pong" sem acordar; sem nada chegando por esse tempo, a conexao esta muda
const PING_INTERVAL_MSEC := 2000
const SILENCE_LIMIT_MSEC := 6000
## quem so recebe confirma por conta propria, senao a sala guarda tudo para um reenvio que nao vem
const ACK_INTERVAL_MSEC := 1000
## a sala guarda a vaga por 60 s; as tentativas param um pouco antes
const RESUME_WINDOW_MSEC := 55000
const RESUME_DELAYS_MSEC := [500, 1000, 2000, 3000, 5000]
## fechamento de quem vai tentar voltar: a sala espera em vez de avisar que saiu
const RESUME_CLOSE_CODE := 4100
## durante a volta, so estes fechamentos encerram as tentativas: a sala nao tem mais a vaga ou acabou.
## Recusa pelo limite de tentativas da rede (a turma toda caindo junto) tenta de novo
const FINAL_RESUME_CODES := [4004, 4009, 4010, 4012]
const DELIBERATE_CLOSE_CODES := [1000, 1001]
## o mesmo teto da fila da sala: passou disso, ela ja desistiu de reenviar para este jogador
const MAX_RETAINED_BYTES := 4 * 1024 * 1024

var room_code := ""
## motivo dado pela sala ao recusar a entrada ou encerrar a partida
var refusal := ""
## ficha de uso unico desta partida: so com ela a sala aceita o relatorio do jogador no fim
var ticket := ""

var _socket := WebSocketPeer.new()
var _base_url := ""
var _id := 0
var _status := CONNECTION_DISCONNECTED
var _peers: Array[int] = []
var _incoming: Array[Dictionary] = []
var _outgoing := StreamPeerBuffer.new()
var _outgoing_records := 0
var _last_flush_msec := 0
var _target_peer := 0
var _transfer_channel := 0
var _transfer_mode := TRANSFER_MODE_RELIABLE
var _refusing := false

## chave dada pela sala na entrada: so com ela da para voltar no lugar deste jogador
var _key := ""
## ultimo pacote numerado que saiu daqui e ultimo que chegou da sala
var _sent := 0
var _received := 0
var _acked_received := 0
## lotes enviados que a sala ainda nao confirmou: {first, count, data}
var _retained: Array[Dictionary] = []
var _retained_bytes := 0
var _resume_broken := false
var _send_queue: Array[Dictionary] = []
var _last_send_msec := -MIN_SEND_SPACING_MSEC
var _last_rx_msec := 0
var _last_tx_msec := 0
var _last_ping_msec := 0
var _resuming := false
var _resume_deadline_msec := 0
var _next_resume_msec := 0
var _resume_tries := 0


func create_host(base_url: String) -> Error:
	_id = HOST_ID
	_base_url = base_url
	return _open("%s/salas?v=%s" % [base_url, PROTOCOL_VERSION])


func create_client(base_url: String, code: String) -> Error:
	_id = new_client_id()
	_base_url = base_url
	return _open("%s/salas/%s?v=%s&id=%d" % [base_url, code.to_upper(), PROTOCOL_VERSION, _id])


## a sala recusa um id repetido; jogos abertos no mesmo instante sairiam com a mesma semente do sorteio global
static func new_client_id() -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([OS.get_process_id(), Time.get_ticks_usec(), Time.get_unix_time_from_system()])
	return rng.randi_range(HOST_ID + 1, MAX_ID)


func is_resuming() -> bool:
	return _resuming


func _open(url: String) -> Error:
	_socket = WebSocketPeer.new()
	_socket.inbound_buffer_size = SOCKET_BUFFER_BYTES
	_socket.outbound_buffer_size = SOCKET_BUFFER_BYTES
	var error := _socket.connect_to_url(url)
	if error == OK and _status == CONNECTION_DISCONNECTED:
		_status = CONNECTION_CONNECTING
	return error


static func encode_record(peer: int, channel: int, mode: int, data: PackedByteArray) -> PackedByteArray:
	var record := StreamPeerBuffer.new()
	record.put_32(peer)
	record.put_8(channel)
	record.put_8(mode)
	record.put_u32(data.size())
	record.put_data(data)
	return record.data_array


static func encode_frame(confirmed: int, first: int, body: PackedByteArray) -> PackedByteArray:
	var frame := StreamPeerBuffer.new()
	frame.put_u32(confirmed)
	frame.put_u32(first)
	frame.put_data(body)
	return frame.data_array


## vazio quando a mensagem esta cortada ou mente o tamanho: a sala nunca manda isso, entao e descartada inteira
static func decode_batch(batch: PackedByteArray) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var reader := StreamPeerBuffer.new()
	reader.data_array = batch
	while reader.get_position() < batch.size():
		if batch.size() - reader.get_position() < HEADER_SIZE:
			return []
		var peer := reader.get_32()
		var channel := reader.get_u8()
		var mode := reader.get_u8()
		var size := reader.get_u32()
		if batch.size() - reader.get_position() < size:
			return []
		var data: PackedByteArray = reader.get_data(size)[1]
		records.append({"peer": peer, "channel": channel, "mode": mode, "data": data})
	return records


func _poll() -> void:
	if _status == CONNECTION_DISCONNECTED:
		return
	_socket.poll()
	# a recusa chega como texto logo antes do fechamento: le em qualquer estado antes de desistir
	_read_messages()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _resuming:
				_keep_alive()
			if not _resuming:
				_flush(false)
				_acknowledge()
		WebSocketPeer.STATE_CLOSED:
			_on_socket_closed()
	if _resuming:
		_try_to_resume()


func _keep_alive() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_ping_msec >= PING_INTERVAL_MSEC:
		_last_ping_msec = now
		_socket.send_text("ping")
	if _status == CONNECTION_CONNECTED and not _key.is_empty() and now - _last_rx_msec > SILENCE_LIMIT_MSEC:
		Net.log_network("a sala ficou muda por %d s, tentando voltar" % (SILENCE_LIMIT_MSEC / 1000))
		_socket.close(RESUME_CLOSE_CODE, "retomando")
		_begin_resume()


func _read_messages() -> void:
	while _status != CONNECTION_DISCONNECTED and _socket.get_available_packet_count() > 0:
		var message := _socket.get_packet()
		_last_rx_msec = Time.get_ticks_msec()
		if _socket.was_string_packet():
			_on_control(message.get_string_from_utf8())
		elif _status == CONNECTION_CONNECTED:
			_on_frame(message)
		if _incoming.size() > MAX_INCOMING:
			refusal = "A conexão recebeu dados demais e foi fechada."
			_drop_connection()


## pacote repetido do reenvio da sala e ignorado. A sala nao guarda posicao para quem esta fora, entao o
## reenvio pula numeros: o que nao veio ja envelheceu
func _on_frame(message: PackedByteArray) -> void:
	if message.size() < STREAM_HEADER_SIZE:
		return
	var reader := StreamPeerBuffer.new()
	reader.data_array = message
	var confirmed := reader.get_u32()
	var first := reader.get_u32()
	_forget_confirmed(confirmed)
	var records := decode_batch(message.slice(STREAM_HEADER_SIZE))
	_received = maxi(_received, first - 1)
	var repeated := _received + 1 - first
	for i in range(repeated, records.size()):
		_received += 1
		if records[i].peer in _peers:
			_incoming.append(records[i])


func _on_control(text: String) -> void:
	if text == "pong":
		return
	var control: Variant = JSON.parse_string(text)
	if not control is Dictionary:
		return
	match control.get("t"):
		"bem-vindo":
			room_code = str(control.get("sala", ""))
			ticket = str(control.get("ficha", ""))
			_key = str(control.get("chave", ""))
			_status = CONNECTION_CONNECTED
			for peer: Variant in control.get("pares", []):
				_add_peer(int(peer))
			room_ready.emit(room_code)
		"retomado":
			_on_resumed(int(control.get("recebido", 0)), control.get("pares", []))
		"entrou":
			_add_peer(int(control.get("id", 0)))
		"saiu":
			_remove_peer(int(control.get("id", 0)))
		"ausente":
			peer_away.emit(int(control.get("id", 0)), true)
		"voltou":
			peer_away.emit(int(control.get("id", 0)), false)
		"erro":
			refusal = str(control.get("motivo", ""))
		"encerrada":
			refusal = str(control.get("motivo", ""))
			_drop_connection()


func _add_peer(peer: int) -> void:
	if peer > 0 and peer != _id and peer not in _peers:
		_peers.append(peer)
		peer_connected.emit(peer)


## o que ainda estava na fila de quem saiu e descartado: o Godot recusaria pacote de par desconhecido
func _remove_peer(peer: int) -> void:
	if peer in _peers:
		_peers.erase(peer)
		_incoming = _incoming.filter(func(record: Dictionary) -> bool: return record.peer != peer)
		peer_disconnected.emit(peer)


# a sala fecha com codigo 4000+ e o motivo no fechamento quando recusa, expira, derruba ou o host sai.
# Queda de rede (sem codigo, 1006) com a chave em maos vira tentativa de voltar
func _on_socket_closed() -> void:
	var code := _socket.get_close_code()
	if refusal.is_empty() and code >= ROOM_CLOSE_CODES:
		refusal = _socket.get_close_reason()
	if _resuming:
		if code in FINAL_RESUME_CODES:
			Net.log_network("a sala recusou a volta: \"%s\"" % refusal)
			_drop_connection()
			return
		if not refusal.is_empty():
			Net.log_network("volta adiada: \"%s\"" % refusal)
			refusal = ""
		# a tentativa que falhou nao e lida de novo a cada quadro ate a proxima
		_socket = WebSocketPeer.new()
		return
	if _can_resume(code):
		Net.log_network("conexão caiu (código %d), tentando voltar para a sala" % code)
		_begin_resume()
		return
	Net.log_network("sala fechou a conexão: código %d, motivo \"%s\"" % [code, refusal if not refusal.is_empty() else _socket.get_close_reason()])
	_drop_connection()


func _can_resume(code: int) -> bool:
	return _status == CONNECTION_CONNECTED and not _key.is_empty() and not _resume_broken and refusal.is_empty() \
		and code not in DELIBERATE_CLOSE_CODES and code < ROOM_CLOSE_CODES


func _begin_resume() -> void:
	if _resume_broken:
		refusal = "A conexão com a sala caiu."
		_drop_connection()
		return
	var now := Time.get_ticks_msec()
	_resuming = true
	_resume_deadline_msec = now + RESUME_WINDOW_MSEC
	_resume_tries = 0
	_next_resume_msec = now + RESUME_DELAYS_MSEC[0]
	_send_queue.clear()
	_socket = WebSocketPeer.new()
	resuming.emit(true)


func _try_to_resume() -> void:
	var now := Time.get_ticks_msec()
	if now > _resume_deadline_msec:
		refusal = "A conexão com a sala caiu e não voltou."
		Net.log_network(refusal)
		_drop_connection()
		return
	var state := _socket.get_ready_state()
	if now < _next_resume_msec or (state != WebSocketPeer.STATE_CLOSED and state != WebSocketPeer.STATE_CLOSING):
		return
	_resume_tries += 1
	_next_resume_msec = now + RESUME_DELAYS_MSEC[mini(_resume_tries, RESUME_DELAYS_MSEC.size() - 1)]
	_open("%s/salas/%s?v=%s&id=%d&retomar=%s&recebido=%d" % [_base_url, room_code, PROTOCOL_VERSION, _id, _key, _received])


## a sala diz ate onde recebeu daqui: o resto sai de novo, em poucos lotes grandes e antes de qualquer
## pacote novo. Quem saiu ou entrou durante a queda chega pela lista de pares
func _on_resumed(room_received: int, room_peers: Array) -> void:
	if _resume_broken:
		refusal = "A conexão ficou fora por tempo demais."
		_drop_connection()
		return
	_resuming = false
	_last_rx_msec = Time.get_ticks_msec()
	_forget_confirmed(room_received)
	_send_queue.assign(_merge_for_resend(_retained))
	var present: Array[int] = []
	present.assign(room_peers.map(func(peer: Variant) -> int: return int(peer)))
	for peer in _peers.duplicate():
		if peer not in present:
			_remove_peer(peer)
	for peer in present:
		_add_peer(peer)
	Net.log_network("voltou para a sala depois de %d tentativa(s)" % _resume_tries)
	resuming.emit(false)


static func _merge_for_resend(chunks: Array[Dictionary]) -> Array[Dictionary]:
	var merged: Array[Dictionary] = []
	for chunk in chunks:
		var last: Dictionary = merged.back() if not merged.is_empty() else {}
		if not last.is_empty() and last.data.size() + chunk.data.size() <= MAX_BATCH_BYTES and last.count + chunk.count <= MAX_BATCH_RECORDS:
			merged[merged.size() - 1] = {"first": last.first, "count": last.count + chunk.count, "data": last.data + chunk.data}
		else:
			merged.append(chunk)
	return merged


func _forget_confirmed(confirmed: int) -> void:
	while not _retained.is_empty() and _retained[0].first + _retained[0].count - 1 <= confirmed:
		_retained_bytes -= _retained[0].data.size()
		_retained.pop_front()


func _retain(chunk: Dictionary) -> void:
	if _resume_broken or _key.is_empty():
		return
	_retained.append(chunk)
	_retained_bytes += chunk.data.size()
	if _retained_bytes > MAX_RETAINED_BYTES:
		_resume_broken = true
		_retained.clear()
		_retained_bytes = 0


## quem desistiu de voltar nao recebe resuming(false): a partida cai e o aviso de volta seria mentira
func _drop_connection() -> void:
	_resuming = false
	for peer in _peers.duplicate():
		_remove_peer(peer)
	_incoming.clear()
	_outgoing.clear()
	_outgoing_records = 0
	_send_queue.clear()
	_retained.clear()
	_retained_bytes = 0
	_status = CONNECTION_DISCONNECTED
	if _socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_socket.close()
	dropped.emit()


func _flush(now: bool) -> void:
	if _outgoing.get_size() > 0 and (now or Time.get_ticks_msec() - _last_flush_msec >= FLUSH_INTERVAL_MSEC):
		var chunk := {"first": _sent + 1, "count": _outgoing_records, "data": _outgoing.data_array}
		_sent += _outgoing_records
		_retain(chunk)
		if not _resuming:
			_send_queue.append(chunk)
		_outgoing.clear()
		_outgoing_records = 0
		_last_flush_msec = Time.get_ticks_msec()
	_drain_queue()


func _drain_queue() -> void:
	while not _send_queue.is_empty() and not _resuming and _may_send():
		var chunk: Dictionary = _send_queue.pop_front()
		_send_frame(chunk.first, chunk.data)


func _may_send() -> bool:
	return Time.get_ticks_msec() - _last_send_msec >= MIN_SEND_SPACING_MSEC


func _send_frame(first: int, body: PackedByteArray) -> void:
	_send_batch(encode_frame(_received, first, body))
	_acked_received = _received
	_last_tx_msec = Time.get_ticks_msec()
	_last_send_msec = _last_tx_msec


func _acknowledge() -> void:
	if _received > _acked_received and _send_queue.is_empty() and Time.get_ticks_msec() - _last_tx_msec >= ACK_INTERVAL_MSEC and _may_send():
		_send_frame(_sent + 1, PackedByteArray())


func _send_batch(data: PackedByteArray) -> void:
	_socket.send(data)


func _send_control(control: Dictionary) -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(control))


## durante a volta, posicao e outros pacotes que envelhecem rapido ficam de fora: so o que nao pode se
## perder espera para sair de novo
func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _status != CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	if buffer.size() > _get_max_packet_size():
		return ERR_OUT_OF_MEMORY
	if _resuming and _transfer_mode != TRANSFER_MODE_RELIABLE:
		return OK
	if _outgoing.get_size() + HEADER_SIZE + buffer.size() > MAX_BATCH_BYTES or _outgoing_records >= MAX_BATCH_RECORDS:
		_flush(true)
	_outgoing.put_data(encode_record(_target_peer, _transfer_channel, _transfer_mode, buffer))
	_outgoing_records += 1
	return OK


func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	return _incoming.pop_front().data


func _get_available_packet_count() -> int:
	return _incoming.size()


func _get_packet_peer() -> int:
	return _incoming[0].peer if not _incoming.is_empty() else 0


func _get_packet_channel() -> int:
	return _incoming[0].channel if not _incoming.is_empty() else 0


func _get_packet_mode() -> TransferMode:
	return _incoming[0].mode if not _incoming.is_empty() else TRANSFER_MODE_RELIABLE


func _get_max_packet_size() -> int:
	return MAX_BATCH_BYTES - HEADER_SIZE


func _set_target_peer(peer: int) -> void:
	_target_peer = peer


func _set_transfer_channel(channel: int) -> void:
	_transfer_channel = channel


func _get_transfer_channel() -> int:
	return _transfer_channel


func _set_transfer_mode(mode: TransferMode) -> void:
	_transfer_mode = mode


func _get_transfer_mode() -> TransferMode:
	return _transfer_mode


func _get_unique_id() -> int:
	return _id


func _is_server() -> bool:
	return _id == HOST_ID


## a sala ja entrega os pacotes entre clientes; o Godot nao precisa repassar pelo host
func _is_server_relay_supported() -> bool:
	return false


func _get_connection_status() -> ConnectionStatus:
	return _status


func _set_refuse_new_connections(enable: bool) -> void:
	_refusing = enable
	if enable and _is_server():
		_send_control({"t": "trancar"})


func _is_refusing_new_connections() -> bool:
	return _refusing


func _disconnect_peer(peer: int, _force: bool) -> void:
	if _is_server():
		_send_control({"t": "expulsar", "id": peer})


## o host avisa a sala antes de sair: os outros ficam sabendo na hora, sem esperar a conexao cair
func _close() -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN and not _resuming:
		_flush(true)
		_send_queue.assign(_merge_for_resend(_send_queue))
		while not _send_queue.is_empty():
			var chunk: Dictionary = _send_queue.pop_front()
			_send_frame(chunk.first, chunk.data)
		if _is_server():
			_send_control({"t": "encerrar"})
		# despacha o que ficou na fila antes do aviso de fechamento
		_socket.poll()
		_socket.close()
	elif _socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_socket.close()
	_resuming = false
	_peers.clear()
	_incoming.clear()
	_outgoing.clear()
	_outgoing_records = 0
	_send_queue.clear()
	_retained.clear()
	_retained_bytes = 0
	_status = CONNECTION_DISCONNECTED
