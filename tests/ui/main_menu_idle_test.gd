extends GdUnitTestSuite

# menu parado vira vitrine: 20 s sem ninguém mexer e o jogo volta ao teaser

const MENU := preload("res://scenes/ui/main_menu.tscn")


func _open_menu() -> Node:
	var menu: Node = auto_free(MENU.instantiate())
	menu.idle_scene = ""
	add_child(menu)
	return menu


func _wait_idle(menu: Node, seconds: float) -> void:
	menu._process(seconds)


func test_twenty_seconds_without_input_go_back_to_the_teaser() -> void:
	var menu := _open_menu()

	_wait_idle(menu, menu.IDLE_TEASER_SECONDS - 0.5)
	assert_bool(menu.returned_to_teaser).is_false()
	_wait_idle(menu, 1.0)

	assert_bool(menu.returned_to_teaser).is_true()
	assert_str(auto_free(MENU.instantiate()).idle_scene).is_equal("res://scenes/cutscenes/teaser_intro.tscn")


func test_any_key_click_mouse_move_or_gamepad_button_restarts_the_count() -> void:
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(10, 0)
	var click := InputEventMouseButton.new()
	click.pressed = true
	for event: InputEvent in [InputEventKey.new(), click, motion, InputEventJoypadButton.new()]:
		var menu := _open_menu()
		_wait_idle(menu, menu.IDLE_TEASER_SECONDS - 1.0)

		menu._input(event)
		_wait_idle(menu, 2.0)

		assert_bool(menu.returned_to_teaser).override_failure_message("%s não zerou a contagem" % event.get_class()).is_false()


func test_a_resting_stick_does_not_count_as_moving() -> void:
	var menu := _open_menu()
	var drift := InputEventJoypadMotion.new()
	drift.axis_value = 0.1

	_wait_idle(menu, menu.IDLE_TEASER_SECONDS - 1.0)
	menu._input(drift)
	_wait_idle(menu, 2.0)

	assert_bool(menu.returned_to_teaser).is_true()


# lendo as configurações ou o placar, o jogador não perde a tela
func test_an_open_panel_holds_the_menu() -> void:
	var menu := _open_menu()

	menu._open_settings()
	_wait_idle(menu, menu.IDLE_TEASER_SECONDS * 2)

	assert_bool(menu.returned_to_teaser).is_false()
	menu._close_settings()
	assert_float(menu.idle_seconds).is_equal(0.0)


func test_a_pushed_stick_or_a_touch_restart_the_count() -> void:
	var push := InputEventJoypadMotion.new()
	push.axis_value = 0.9
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	for event: InputEvent in [push, touch]:
		var menu := _open_menu()
		_wait_idle(menu, menu.IDLE_TEASER_SECONDS - 1.0)

		menu._input(event)
		_wait_idle(menu, 2.0)

		assert_bool(menu.returned_to_teaser).override_failure_message("%s não zerou a contagem" % event.get_class()).is_false()


# o motivo da partida caída só aparece uma vez: o menu espera o jogador ler
func test_the_dropped_match_notice_holds_the_menu() -> void:
	var menu := _open_menu()
	(menu.get_node("%Notice") as Label).show()

	_wait_idle(menu, menu.IDLE_TEASER_SECONDS * 2)

	assert_bool(menu.returned_to_teaser).is_false()
