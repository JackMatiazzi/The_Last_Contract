extends GdUnitTestSuite

const VICTORY := preload("res://scenes/ui/victory_screen.tscn")

var screen: VictoryScreen
var _saved_name := ""


func before_test() -> void:
	_saved_name = Settings.player_name
	screen = auto_free(VICTORY.instantiate())
	add_child(screen)
	await await_idle_frame()


func after_test() -> void:
	Settings.set_value(&"player_name", _saved_name)


func test_summary_names_who_signed_the_contract() -> void:
	Settings.set_value(&"player_name", "Ana")

	screen.open(2)

	assert_str(screen.summary_label.text).contains("Ana")
	assert_str(screen.summary_label.text).contains("tentativa II")


func test_signatures_read_like_a_list() -> void:
	assert_str(VictoryScreen.join_names(["Ana"])).is_equal("Ana")
	assert_str(VictoryScreen.join_names(["Ana", "Bia"])).is_equal("Ana e Bia")
	assert_str(VictoryScreen.join_names(["Ana", "Bia", "Caio"])).is_equal("Ana, Bia e Caio")
