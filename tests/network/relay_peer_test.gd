extends GdUnitTestSuite

# o formato precisa bater com relay/src/protocolo.js: os dois lados leem as mensagens um do outro


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
