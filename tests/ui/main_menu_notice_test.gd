extends GdUnitTestSuite

# a partida em grupo caiu e o jogo voltou ao menu sem dizer por quê: o motivo da sala aparece no menu

const MENU := preload("res://scenes/ui/main_menu.tscn")


func after_test() -> void:
	Net.last_error = ""


func _open_menu() -> Node:
	var menu: Node = auto_free(MENU.instantiate())
	add_child(menu)
	return menu


func test_the_reason_the_room_closed_shows_on_the_menu() -> void:
	Net.last_error = "A sala chegou ao tempo máximo."

	var menu := _open_menu()

	var notice := menu.get_node("%Notice") as Label
	assert_bool(notice.visible).is_true()
	assert_str(notice.text).contains("A sala chegou ao tempo máximo.")
	assert_str(Net.last_error).is_empty()


func test_without_a_problem_the_menu_shows_no_notice() -> void:
	var menu := _open_menu()

	assert_bool((menu.get_node("%Notice") as Label).visible).is_false()


func test_the_notice_sits_in_the_bottom_right_corner_and_does_not_push_the_menu() -> void:
	var menu := _open_menu()

	var notice := menu.get_node("%Notice") as Label
	assert_bool(menu.get_node("UI/MenuPanel").is_ancestor_of(notice)).is_false()
	assert_float(notice.anchor_left).is_equal(1.0)
	assert_float(notice.anchor_top).is_equal(1.0)
