class_name RelayPeer
extends MultiplayerPeerExtension
## Peer de rede que passa pela sala no Cloudflare (pasta relay/ do projeto). Os pacotes do Godot sao
## juntados e enviados em lotes de FLUSH_INTERVAL: o Cloudflare cobra por mensagem recebida, nao pelo
## tamanho, entao luta com muitos inimigos custa o mesmo que andar pela vila. A sala carimba quem
## mandou cada pacote; ninguem consegue se passar pelo host.

signal room_ready(code: String)
## a conexao com a sala caiu sem o jogo pedir; o Godot so avisa isso para clientes, entao o host ouve aqui
signal dropped

const PROTOCOL_VERSION := "1"
const HOST_ID := 1
const MAX_ID := 0x7FFFFFFF
const FLUSH_INTERVAL_MSEC := 100
## par (int32) | canal (uint8) | modo (uint8) | tamanho (uint32); igual a relay/src/protocolo.js
const HEADER_SIZE := 10
## a sala derruba mensagens acima de 64 KB; o lote sai antes de chegar perto disso
const MAX_BATCH_BYTES := 60000
const SOCKET_BUFFER_BYTES := 1 << 17
## o jogo consome a fila a cada quadro; fila desse tamanho so acontece com alguem inundando a sala
const MAX_INCOMING := 4096
const ROOM_CLOSE_CODES := 4000

var room_code := ""
## motivo dado pela sala ao recusar a entrada ou encerrar a partida
var refusal := ""
## ficha de uso unico desta partida: so com ela a sala aceita o relatorio do jogador no fim
var ticket := ""

var _socket := WebSocketPeer.new()
var _id := 0
var _status := CONNECTION_DISCONNECTED
var _peers: Array[int] = []
var _incoming: Array[Dictionary] = []
var _outgoing := StreamPeerBuffer.new()
var _last_flush_msec := 0
var _target_peer := 0
var _transfer_channel := 0
var _transfer_mode := TRANSFER_MODE_RELIABLE
var _refusing := false


func create_host(base_url: String) -> Error:
	_id = HOST_ID
	return _open("%s/salas?v=%s" % [base_url, PROTOCOL_VERSION])


func create_client(base_url: String, code: String) -> Error:
	_id = randi_range(HOST_ID + 1, MAX_ID)
	return _open("%s/salas/%s?v=%s&id=%d" % [base_url, code.to_upper(), PROTOCOL_VERSION, _id])


func _open(url: String) -> Error:
	_socket.inbound_buffer_size = SOCKET_BUFFER_BYTES
	_socket.outbound_buffer_size = SOCKET_BUFFER_BYTES
	var error := _socket.connect_to_url(url)
	if error == OK:
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
			_flush(false)
		WebSocketPeer.STATE_CLOSED:
			# a sala fecha com codigo 4000+ e o motivo no fechamento quando recusa, expira ou o host sai
			if refusal.is_empty() and _socket.get_close_code() >= ROOM_CLOSE_CODES:
				refusal = _socket.get_close_reason()
			_drop_connection()


func _read_messages() -> void:
	while _status != CONNECTION_DISCONNECTED and _socket.get_available_packet_count() > 0:
		var message := _socket.get_packet()
		if _socket.was_string_packet():
			_on_control(message.get_string_from_utf8())
		elif _status == CONNECTION_CONNECTED:
			for record in decode_batch(message):
				if record.peer in _peers:
					_incoming.append(record)
			if _incoming.size() > MAX_INCOMING:
				refusal = "A conexão recebeu dados demais e foi fechada."
				_drop_connection()


func _on_control(text: String) -> void:
	var control: Variant = JSON.parse_string(text)
	if not control is Dictionary:
		return
	match control.get("t"):
		"bem-vindo":
			room_code = str(control.get("sala", ""))
			ticket = str(control.get("ficha", ""))
			_status = CONNECTION_CONNECTED
			for peer: Variant in control.get("pares", []):
				_add_peer(int(peer))
			room_ready.emit(room_code)
		"entrou":
			_add_peer(int(control.get("id", 0)))
		"saiu":
			_remove_peer(int(control.get("id", 0)))
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


func _drop_connection() -> void:
	for peer in _peers.duplicate():
		_remove_peer(peer)
	_incoming.clear()
	_outgoing.clear()
	_status = CONNECTION_DISCONNECTED
	if _socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_socket.close()
	dropped.emit()


func _flush(now: bool) -> void:
	if _outgoing.get_size() == 0:
		return
	if not now and Time.get_ticks_msec() - _last_flush_msec < FLUSH_INTERVAL_MSEC:
		return
	_socket.send(_outgoing.data_array)
	_outgoing.clear()
	_last_flush_msec = Time.get_ticks_msec()


func _send_control(control: Dictionary) -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(control))


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _status != CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	if buffer.size() > _get_max_packet_size():
		return ERR_OUT_OF_MEMORY
	if _outgoing.get_size() + HEADER_SIZE + buffer.size() > MAX_BATCH_BYTES:
		_flush(true)
	_outgoing.put_data(encode_record(_target_peer, _transfer_channel, _transfer_mode, buffer))
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
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_flush(true)
		if _is_server():
			_send_control({"t": "encerrar"})
		# despacha o que ficou na fila antes do aviso de fechamento
		_socket.poll()
		_socket.close()
	_peers.clear()
	_incoming.clear()
	_outgoing.clear()
	_status = CONNECTION_DISCONNECTED
