extends GdUnitTestSuite

# No lobby, a sala online pelo Cloudflare é o caminho principal: criar a sala ou digitar o código.
# Rede local e túnel continuam disponíveis, guardados em "Outras formas".

const LOBBY := preload("res://scenes/ui/lobby.tscn")

var lobby: Lobby


func before_test() -> void:
	lobby = auto_free(LOBBY.instantiate()) as Lobby
	add_child(lobby)
	await await_idle_frame()


func after_test() -> void:
	Net.leave()


# como quem digita: o campo recebe o texto e avisa que mudou
func _type(text: String) -> void:
	lobby.room_code_input.insert_text_at_caret(text)
	lobby.room_code_input.text_changed.emit(lobby.room_code_input.text)


func test_the_online_room_is_the_first_choice() -> void:
	assert_bool(lobby.create_online_button.is_visible_in_tree()).is_true()
	assert_bool(lobby.room_code_input.is_visible_in_tree()).is_true()
	assert_bool(lobby.create_online_button.has_focus()).is_true()


func test_local_network_and_tunnel_stay_tucked_away_until_asked() -> void:
	assert_bool(lobby.other_ways.visible).is_false()

	lobby.other_ways_toggle.button_pressed = true

	assert_bool(lobby.other_ways.visible).is_true()
	assert_bool(lobby.address_input.is_visible_in_tree()).is_true()


func test_the_other_ways_list_only_local_network_and_tunnel() -> void:
	var ids: Array[int] = []
	for i in lobby.host_mode.item_count:
		ids.append(lobby.host_mode.get_item_id(i))

	assert_array(ids).contains_exactly_in_any_order([Net.Transport.ENET, Net.Transport.WEBSOCKET])


func test_the_room_code_is_written_in_capitals() -> void:
	_type("abc234")

	assert_str(lobby.room_code_input.text).is_equal("ABC234")


func test_joining_waits_for_a_whole_room_code() -> void:
	assert_bool(lobby.join_online_button.disabled).is_true()

	_type("ABC2")
	assert_bool(lobby.join_online_button.disabled).is_true()

	_type("34")
	assert_bool(lobby.join_online_button.disabled).is_false()


func test_the_privacy_notice_is_next_to_the_online_room() -> void:
	var notice := lobby.get_node("%PrivacyHint") as Label

	assert_bool(notice.is_visible_in_tree()).is_true()
	assert_str(notice.text).contains("90 dias")


func test_the_host_names_the_group_and_it_goes_to_the_room() -> void:
	Net.host(Net.PORT, Net.Transport.ENET)
	lobby._show_room(true)

	lobby.group_name_input.text_submitted.emit("Os Desgarrados")

	assert_bool(lobby.group_name_input.editable).is_true()
	assert_str(Net.group_name).is_equal("Os Desgarrados")
