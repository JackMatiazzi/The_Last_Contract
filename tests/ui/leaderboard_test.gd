extends GdUnitTestSuite

# placar do menu: lê o que a API manda (dado de outros jogadores) e mostra grupos e solo

const PANEL := preload("res://scenes/ui/leaderboard_panel.tscn")
const GROUPS := '[{"rotulo": "Lanterna", "jogadores": [{"apelido": "Ana", "classe": "Knight"}, {"apelido": "Beto", "classe": "Mage"}], "tentativas": 2, "minutos": 31.4}, {"rotulo": "Caio, Duda", "jogadores": [{"apelido": "Caio", "classe": "Rogue"}, {"apelido": "Duda", "classe": "Barbarian"}], "tentativas": 3, "minutos": null}]'
const SOLO := '[{"classe": "Mage", "partidas": 5, "vitorias": 2, "melhor_minutos": 28.2, "media_tentativas": 3.4}]'


func test_group_rows_carry_name_players_attempts_and_time() -> void:
	var rows: Array = Leaderboard.parse_groups(GROUPS)

	assert_int(rows.size()).is_equal(2)
	assert_array(rows[0]).contains_exactly(["1", "Lanterna", "Ana, Beto", "2", "31,4 min"])
	assert_array(rows[1]).contains_exactly(["2", "Caio, Duda", "Caio, Duda", "3", "—"])


func test_names_from_other_players_lose_invisible_characters_and_get_cut() -> void:
	var raw := '[{"rotulo": "Gru\\u202epo com um nome comprido demais para caber", "jogadores": [{"apelido": "An\\u200ba", "classe": "Knight"}], "tentativas": 1, "minutos": 10}]'

	var row: Array = Leaderboard.parse_groups(raw)[0]

	assert_str(row[1]).is_equal(Net.clean_text("Grupo com um nome comprido demais para caber", Net.MAX_GROUP_NAME_LENGTH))
	assert_str(row[2]).is_equal("Ana")


func test_solo_shows_every_class_even_without_matches() -> void:
	var rows: Array = Leaderboard.parse_solo(SOLO)

	assert_int(rows.size()).is_equal(4)
	assert_array(rows.map(func(row: Array) -> String: return row[0])).contains_exactly(["Knight", "Barbarian", "Mage", "Rogue"])
	assert_array(rows[2]).contains_exactly(["Mage", "5", "2", "28,2 min", "3,4"])
	assert_array(rows[0]).contains_exactly(["Knight", "0", "0", "—", "—"])


func test_a_broken_answer_is_reported_as_unreadable() -> void:
	assert_object(Leaderboard.parse_groups("<html>erro</html>")).is_null()
	assert_object(Leaderboard.parse_solo('{"erro": "x"}')).is_null()


func _panel() -> LeaderboardPanel:
	var panel: LeaderboardPanel = auto_free(PANEL.instantiate())
	add_child(panel)
	return panel


func test_the_panel_lists_the_groups_it_received() -> void:
	var panel := _panel()

	panel.show_groups(true, GROUPS)

	assert_int(panel.group_rows.get_child_count()).is_equal(2)
	assert_bool(panel.group_status.visible).is_false()


func test_no_group_match_yet_says_so() -> void:
	var panel := _panel()

	panel.show_groups(true, "[]")

	assert_str(panel.group_status.text).contains("Nenhum contrato em grupo")
	assert_bool(panel.group_status.visible).is_true()


func test_without_internet_the_panel_offers_to_try_again() -> void:
	var panel := _panel()

	panel.show_groups(false, "")

	assert_str(panel.group_status.text).contains("Não foi possível")
	assert_bool(panel.retry_button.visible).is_true()


func test_the_main_menu_has_the_leaderboard_between_group_and_settings() -> void:
	var menu: Node = auto_free(load("res://scenes/ui/main_menu.tscn").instantiate())
	var buttons := menu.get_node("UI/MenuPanel/Column/Buttons")

	var order := buttons.get_children().map(func(button: Button) -> String: return button.text)

	assert_array(order).contains_exactly(["Aceitar contrato", "Contrato em grupo", "Placar", "Configurações", "Sair"])


func test_solo_without_any_victory_says_nobody_won_yet() -> void:
	var panel := _panel()

	panel.show_solo(true, '[{"classe": "Knight", "partidas": 3, "vitorias": 0, "melhor_minutos": null, "media_tentativas": 4}]')

	assert_int(panel.solo_rows.get_child_count()).is_equal(4)
	assert_str(panel.solo_status.text).is_equal(LeaderboardPanel.NO_SOLO)
	assert_bool(panel.solo_status.visible).is_true()
