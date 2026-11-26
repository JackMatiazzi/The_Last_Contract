extends GdUnitTestSuite

# o formato precisa bater com src/protocolo.js da API (the-last-contract-api): os dois lados leem as mensagens um do outro


func _record(peer: int, channel: int, mode: int, bytes: Array) -> PackedByteArray:
	return RelayPeer.encode_record(peer, channel, mode, PackedByteArray(bytes))


func test_records_come_back_the_same_after_a_batch() -> void:
	var batch := _record(1, 0, 2, [1, 2, 3]) + _record(-7, 3, 0, []) + _record(12345, 1, 1, [9, 9])

	var records := RelayPeer.decode_batch(batch)

	assert_int(records.size()).is_equal(3)
	assert_int(records[0].peer).is_equal(1)
	assert_array(Array(records[0].data)).is_equal([1, 2, 3])
	assert_int(records[1].peer).is_equal(-7)
	assert_int(records[1].channel).is_equal(3)
	assert_int(records[2].mode).is_equal(1)


func test_record_header_matches_the_relay_layout() -> void:
	var record := _record(-2, 5, 1, [42])

	assert_int(record.size()).is_equal(RelayPeer.HEADER_SIZE + 1)
	assert_int(record.decode_s32(0)).is_equal(-2)
	assert_int(record.decode_u8(4)).is_equal(5)
	assert_int(record.decode_u8(5)).is_equal(1)
	assert_int(record.decode_u32(6)).is_equal(1)


func test_a_cut_batch_is_dropped_whole() -> void:
	var batch := _record(1, 0, 0, [1, 2, 3, 4]) + _record(1, 0, 0, [5, 6])

	assert_array(RelayPeer.decode_batch(batch.slice(0, batch.size() - 1))).is_empty()
	assert_array(RelayPeer.decode_batch(batch.slice(0, 5))).is_empty()


func test_a_lying_size_is_dropped() -> void:
	var batch := _record(1, 0, 0, [1, 2])
	batch.encode_u32(6, 99999)

	assert_array(RelayPeer.decode_batch(batch)).is_empty()


func test_nothing_is_sent_before_the_room_answers() -> void:
	var peer := RelayPeer.new()
	peer.create_client("ws://127.0.0.1:9", "ABC234")

	assert_int(peer.put_packet(PackedByteArray([1]))).is_equal(ERR_UNCONFIGURED)
	assert_int(peer.get_connection_status()).is_equal(MultiplayerPeer.CONNECTION_CONNECTING)
	peer.close()


func test_client_ids_never_collide_with_the_host() -> void:
	for i in 50:
		var peer := RelayPeer.new()
		peer.create_client("ws://127.0.0.1:9", "ABC234")
		assert_int(peer.get_unique_id()).is_greater(RelayPeer.HOST_ID)
		peer.close()


# dois jogos abertos no mesmo instante sorteavam o mesmo id e a sala recusava o segundo (código 4003)
func test_client_ids_do_not_follow_the_global_seed() -> void:
	seed(7)
	var first := RelayPeer.new_client_id()
	OS.delay_usec(50)
	seed(7)
	var second := RelayPeer.new_client_id()

	assert_int(first).is_not_equal(second)
	assert_int(first).is_between(RelayPeer.HOST_ID + 1, RelayPeer.MAX_ID)


# a sala derruba quem manda mais de 512 pacotes numa mensagem: o lote sai antes, por maior que seja a rajada
class RecordingPeer extends RelayPeer:
	var batches: Array[PackedByteArray] = []

	func _send_batch(data: PackedByteArray) -> void:
		batches.append(data)

	func connected() -> RecordingPeer:
		_status = MultiplayerPeer.CONNECTION_CONNECTED
		_key = "chave"
		return self

	func frame_header(index: int) -> Vector2i:
		var reader := StreamPeerBuffer.new()
		reader.data_array = batches[index]
		var confirmed := reader.get_u32()
		return Vector2i(confirmed, reader.get_u32())


func test_a_burst_of_small_packets_never_goes_over_the_room_limit_in_one_message() -> void:
	var peer := RecordingPeer.new().connected()
	for i in 1000:
		peer._put_packet_script(PackedByteArray([i % 256, 1, 2]))
	peer._flush(true)

	var counts := peer._retained.map(func(chunk: Dictionary) -> int: return RelayPeer.decode_batch(chunk.data).size())
	assert_int(counts.reduce(func(total: int, count: int) -> int: return total + count, 0)).is_equal(1000)
	assert_bool(counts.all(func(count: int) -> bool: return count <= RelayPeer.MAX_BATCH_RECORDS)).is_true()
	assert_int(RelayPeer.MAX_BATCH_RECORDS).is_less(512)


func _frame_from_room(confirmed: int, first: int, peers: Array) -> PackedByteArray:
	var body := PackedByteArray()
	for peer: int in peers:
		body.append_array(RelayPeer.encode_record(peer, 0, MultiplayerPeer.TRANSFER_MODE_RELIABLE, PackedByteArray([peer])))
	return RelayPeer.encode_frame(confirmed, first, body)


func test_each_batch_carries_its_first_packet_number_and_what_came_from_the_room() -> void:
	var peer := RecordingPeer.new().connected()
	peer._received = 5
	peer._put_packet_script(PackedByteArray([1]))
	peer._put_packet_script(PackedByteArray([2]))
	peer._flush(true)
	peer._put_packet_script(PackedByteArray([3]))
	peer._last_send_msec -= RelayPeer.MIN_SEND_SPACING_MSEC
	peer._flush(true)

	assert_that(peer.frame_header(0)).is_equal(Vector2i(5, 1))
	assert_that(peer.frame_header(1)).is_equal(Vector2i(5, 3))


func test_packets_the_room_sends_again_after_a_resume_arrive_once() -> void:
	var peer := RecordingPeer.new().connected()
	peer._peers.assign([1])
	peer._on_frame(_frame_from_room(0, 1, [1, 1]))

	peer._on_frame(_frame_from_room(0, 2, [1, 1]))

	assert_int(peer._received).is_equal(3)
	assert_int(peer._get_available_packet_count()).is_equal(3)


# a sala nao guarda posicao para quem esta fora: o reenvio pula os numeros dela
func test_numbers_skipped_by_the_resend_are_jumped_over() -> void:
	var peer := RecordingPeer.new().connected()
	peer._peers.assign([1])
	peer._on_frame(_frame_from_room(0, 1, [1]))

	peer._on_frame(_frame_from_room(0, 4, [1, 1]))

	assert_int(peer._received).is_equal(5)
	assert_int(peer._get_available_packet_count()).is_equal(3)
	assert_int(peer.get_connection_status()).is_equal(MultiplayerPeer.CONNECTION_CONNECTED)


func test_what_the_room_confirms_is_no_longer_kept_for_a_resend() -> void:
	var peer := RecordingPeer.new().connected()
	for i in 3:
		peer._put_packet_script(PackedByteArray([i]))
		peer._flush(true)

	peer._on_frame(_frame_from_room(2, 1, []))

	assert_int(peer._retained.size()).is_equal(1)
	assert_int(peer._retained[0].first).is_equal(3)


func test_while_resuming_only_reliable_packets_wait_to_go_out_again() -> void:
	var peer := RecordingPeer.new().connected()
	peer._begin_resume()
	peer._set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	peer._put_packet_script(PackedByteArray([1]))
	peer._set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	peer._put_packet_script(PackedByteArray([2]))
	peer._flush(true)

	assert_int(peer.batches.size()).is_equal(0)
	assert_int(peer._retained.size()).is_equal(1)
	assert_int(peer._retained[0].count).is_equal(1)
	assert_int(peer.get_connection_status()).is_equal(MultiplayerPeer.CONNECTION_CONNECTED)


# um minuto fora junta centenas de lotes; a sala derruba quem manda mais de 15 mensagens num segundo
func test_the_resend_after_a_resume_goes_in_few_big_messages_and_skips_what_the_room_has() -> void:
	var peer := RecordingPeer.new().connected()
	peer._begin_resume()
	for i in 600:
		peer._put_packet_script(PackedByteArray([i % 256, 1, 2, 3]))
		peer._flush(true)

	peer._on_resumed(100, [])
	var queued := peer._send_queue.duplicate()
	peer._drain_queue()

	assert_bool(peer.is_resuming()).is_false()
	assert_int(queued.size()).is_equal(2)
	assert_int(queued[0].first).is_equal(101)
	assert_int(queued.reduce(func(total: int, chunk: Dictionary) -> int: return total + RelayPeer.decode_batch(chunk.data).size(), 0)).is_equal(500)
	assert_int(peer.batches.size()).is_equal(1)
	assert_that(peer.frame_header(0)).is_equal(Vector2i(0, 101))


# a janela da sala e fixa e comeca na primeira mensagem: duas rajadas de 10 perto da virada passariam de 15
func test_batches_leave_at_least_the_spacing_apart() -> void:
	var peer := RecordingPeer.new().connected()
	for i in 5:
		peer._put_packet_script(PackedByteArray([i]))
		peer._flush(true)

	assert_int(peer.batches.size()).is_equal(1)
	assert_int(peer._send_queue.size()).is_equal(4)
	peer._last_send_msec -= RelayPeer.MIN_SEND_SPACING_MSEC
	peer._drain_queue()
	assert_int(peer.batches.size()).is_equal(2)


func test_peers_that_left_while_this_one_was_away_leave_here_too() -> void:
	var peer := RecordingPeer.new().connected()
	peer._peers.assign([1, 500])
	var gone: Array[int] = []
	peer.peer_disconnected.connect(func(id: int) -> void: gone.append(id))
	peer._begin_resume()

	peer._on_resumed(0, [1.0])

	assert_array(gone).is_equal([500])
	assert_array(peer._peers).is_equal([1])


func test_only_a_network_drop_turns_into_a_resume() -> void:
	var peer := RecordingPeer.new().connected()

	assert_bool(peer._can_resume(1006)).is_true()
	assert_bool(peer._can_resume(-1)).is_true()
	assert_bool(peer._can_resume(1000)).is_false()
	assert_bool(peer._can_resume(4004)).is_false()
	assert_bool(peer._can_resume(4008)).is_false()
	peer._key = ""
	assert_bool(peer._can_resume(1006)).is_false()


func test_the_resume_gives_up_after_the_window_and_drops() -> void:
	var peer := RecordingPeer.new().connected()
	monitor_signals(peer)
	peer._begin_resume()

	peer._resume_deadline_msec = Time.get_ticks_msec() - 1
	peer._try_to_resume()

	await assert_signal(peer).is_emitted("dropped")
	assert_str(peer.refusal).contains("não voltou")


# a turma inteira atrás do mesmo IP caindo junto bate no limite de tentativas da rede: espera e tenta de novo
func test_a_refusal_for_too_many_tries_keeps_resuming() -> void:
	var peer := RecordingPeer.new().connected()
	peer._begin_resume()

	peer._on_control(JSON.stringify({"t": "erro", "motivo": "Muitas tentativas de entrar. Espere um minuto."}))
	peer._on_socket_closed()

	assert_bool(peer.is_resuming()).is_true()
	assert_str(peer.refusal).is_empty()
	assert_int(peer.get_connection_status()).is_equal(MultiplayerPeer.CONNECTION_CONNECTED)


func test_a_quiet_receiver_still_confirms_what_it_got() -> void:
	var peer := RecordingPeer.new().connected()
	peer._peers.assign([1])
	peer._on_frame(_frame_from_room(0, 1, [1, 1]))
	peer._last_tx_msec = Time.get_ticks_msec() - RelayPeer.ACK_INTERVAL_MSEC

	peer._acknowledge()
	peer._acknowledge()

	assert_int(peer.batches.size()).is_equal(1)
	assert_that(peer.frame_header(0)).is_equal(Vector2i(2, 1))
	assert_int(peer.batches[0].size()).is_equal(RelayPeer.STREAM_HEADER_SIZE)


# a volta que estourou a fila daqui perderia pacote confiavel sem ninguem saber: vira queda
func test_a_resume_after_the_local_queue_overflowed_drops_instead() -> void:
	var peer := RecordingPeer.new().connected()
	monitor_signals(peer)
	peer._begin_resume()
	peer._resume_broken = true

	peer._on_resumed(0, [])

	await assert_signal(peer).is_emitted("dropped")
	await assert_signal(peer).is_not_emitted("resuming", [false])
