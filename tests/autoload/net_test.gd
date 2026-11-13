extends GdUnitTestSuite

const TEST_PORT := 17790

var _roster_before: Dictionary
var _names_before: Dictionary


func before_test() -> void:
	_roster_before = Net.roster.duplicate()
	_names_before = Net.names.duplicate()


func after_test() -> void:
	Net.leave()
	Net.roster = _roster_before
	Net.names = _names_before


func test_names_are_trimmed_and_cut() -> void:
	assert_str(Net.clean_name("  Jackson  ")).is_equal("Jackson")
	assert_int(Net.clean_name("a".repeat(40)).length()).is_equal(Net.MAX_NAME_LENGTH)


func test_empty_names_fall_back_to_a_default() -> void:
	assert_str(Net.clean_name("   ")).is_equal("Aventureiro")


func test_control_characters_are_removed_from_names() -> void:
	assert_str(Net.clean_name("And\nré\t")).is_equal("André")


func test_an_adventurer_chosen_by_someone_else_is_taken() -> void:
	Net.roster = {1: 0, 2: 1}

	assert_bool(Net.is_taken(1)).is_true()
	assert_bool(Net.is_taken(0)).is_false()
	assert_bool(Net.is_taken(2)).is_false()


func test_the_match_starts_only_when_everyone_chose() -> void:
	Net.roster = {1: 0, 2: Net.NO_CHOICE}
	assert_bool(Net.can_start()).is_false()

	Net.roster = {1: 0, 2: 3}
	assert_bool(Net.can_start()).is_true()


func test_only_listed_peers_count_as_players() -> void:
	Net.roster = {1: 0, 2: 1}

	assert_bool(Net.is_player(2)).is_true()
	assert_bool(Net.is_player(99)).is_false()


func test_shareable_addresses_skip_loopback_ipv6_and_virtual_adapters() -> void:
	for entry in Net.shareable_addresses():
		assert_bool(entry.address.begins_with("127.")).is_false()
		assert_int(entry.address.count(".")).is_equal(3)
		assert_bool(entry.label.to_lower().contains("virtualbox")).is_false()


func test_invisible_and_direction_characters_are_removed_from_names() -> void:
	var raw := "An%sd%sr%se%s" % [char(0x202E), char(0x200B), char(0x7F), char(0x85)]

	assert_str(Net.clean_name(raw)).is_equal("Andre")


func test_after_the_match_starts_nobody_changes_adventurer() -> void:
	Net.roster = {1: 0}
	Net.in_match = true

	Net._request_choice(2)

	assert_dict(Net.roster).is_equal({1: 0})
	Net.in_match = false


func test_names_made_only_of_blank_lookalikes_fall_back_to_the_default() -> void:
	var blank := "%s%s%s" % [char(0x3164), char(0x2800), char(0xAD)]

	assert_str(Net.clean_name(blank)).is_equal("Aventureiro")
	assert_str(Net.clean_name("Ana%s" % char(0xE0041))).is_equal("Ana")


func test_tunnel_links_become_websocket_addresses() -> void:
	assert_str(Net.web_address("https://abc-def.trycloudflare.com")).is_equal("wss://abc-def.trycloudflare.com")
	assert_str(Net.web_address("  http://192.168.0.10:7777/ ")).is_equal("ws://192.168.0.10:7777")
	assert_str(Net.web_address("wss://sala.exemplo.com")).is_equal("wss://sala.exemplo.com")


func test_plain_addresses_stay_on_the_local_network_transport() -> void:
	assert_str(Net.web_address("192.168.0.10")).is_empty()
	assert_str(Net.web_address("meu-pc.local")).is_empty()
	assert_str(Net.web_address("ftp://192.168.0.10")).is_empty()


func test_hosting_over_websocket_uses_a_websocket_peer() -> void:
	assert_int(Net.host(TEST_PORT, Net.Transport.WEBSOCKET)).is_equal(OK)

	assert_object(multiplayer.multiplayer_peer).is_instanceof(WebSocketMultiplayerPeer)
	assert_bool(Net.is_online()).is_true()


func test_hosting_on_the_local_network_still_uses_enet() -> void:
	assert_int(Net.host(TEST_PORT)).is_equal(OK)

	assert_object(multiplayer.multiplayer_peer).is_instanceof(ENetMultiplayerPeer)


func test_a_full_party_turns_new_players_away() -> void:
	Net.roster = {1: 0, 2: 1, 3: 2}
	assert_bool(Net.admits_new_player()).is_true()

	Net.roster = {1: 0, 2: 1, 3: 2, 4: 3}

	assert_bool(Net.admits_new_player()).is_false()


func test_nobody_joins_after_the_match_starts() -> void:
	Net.roster = {1: 0}
	Net.in_match = true

	assert_bool(Net.admits_new_player()).is_false()
	Net.in_match = false


func test_names_from_the_host_are_cleaned_again() -> void:
	Net._sync_roster({1: 0, 2: 1}, {1: "Host\n", 2: "Ana%s" % char(0x202E)}, true)

	assert_str(Net.names[1]).is_equal("Host")
	assert_str(Net.names[2]).is_equal("Ana")


func test_tunnel_links_are_recognized_in_any_case() -> void:
	assert_str(Net.web_address("HTTPS://Abc.TryCloudflare.com")).is_equal("wss://Abc.TryCloudflare.com")


func test_a_roster_with_an_unknown_adventurer_is_ignored() -> void:
	Net.roster = {1: 0}

	Net._sync_roster({1: 0, 2: 99}, {}, true)
	Net._sync_roster({1: 0, "2": 1}, {}, true)

	assert_dict(Net.roster).is_equal({1: 0})


func test_someone_turned_away_never_counts_as_a_player_leaving() -> void:
	Net.roster = {1: 0, 2: 1}
	var left: Array[int] = []
	var on_left := func(peer_id: int) -> void: left.append(peer_id)
	Net.player_left.connect(on_left)

	Net._on_peer_disconnected(99)
	Net._on_peer_disconnected(2)

	Net.player_left.disconnect(on_left)
	assert_array(left).contains_exactly([2])


func test_a_choice_from_someone_outside_the_party_is_ignored() -> void:
	Net.roster = {1: 0}

	Net._request_choice(2)

	assert_dict(Net.roster).is_equal({1: 0})


func test_a_roster_larger_than_the_party_is_ignored() -> void:
	Net.roster = {1: 0}
	var oversized := {}
	for peer_id in range(1, Net.MAX_PLAYERS + 2):
		oversized[peer_id] = Net.NO_CHOICE

	Net._sync_roster(oversized, {}, true)

	assert_dict(Net.roster).is_equal({1: 0})
