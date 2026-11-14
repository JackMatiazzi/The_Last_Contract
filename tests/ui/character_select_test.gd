extends GdUnitTestSuite

const CHARACTER_SELECT := preload("res://scenes/ui/character_select.tscn")

var screen: CharacterSelect


func before_test() -> void:
	screen = auto_free(CHARACTER_SELECT.instantiate())
	add_child(screen)
	await await_idle_frame()


# espera as animacoes acabarem
func _choose(index: int) -> void:
	screen.picker.select(index)
	var limit := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < limit:
		await await_idle_frame()
		if not get_tree().get_processed_tweens().any(func(tween: Tween) -> bool: return tween.is_running()):
			return


func test_shows_one_model_per_adventurer() -> void:
	assert_int(screen.models.size()).is_equal(RunState.ADVENTURERS.size())


func test_chosen_adventurer_steps_forward() -> void:
	await _choose(2)

	for i in screen.models.size():
		if i != 2:
			assert_float(screen.models[2].position.z).is_greater(screen.models[i].position.z)


func test_ring_marks_the_chosen_adventurer() -> void:
	await _choose(3)

	assert_float(screen.ring.position.x).is_equal_approx(screen.models[3].position.x, 0.01)


func test_accepting_asks_for_the_signature_first() -> void:
	screen.picker.confirmed.emit(screen.picker.selected)

	assert_bool(screen.contract.visible).is_true()
	assert_bool(screen.picker.visible).is_false()


func test_hidden_picker_ignores_esc_while_signing() -> void:
	screen.picker.confirmed.emit(screen.picker.selected)
	var signals := monitor_signals(screen.picker)

	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	screen.picker._input(event)

	await assert_signal(signals).wait_until(200).is_not_emitted("back_requested")


func test_going_back_from_the_contract_returns_to_the_choice() -> void:
	screen.picker.confirmed.emit(screen.picker.selected)

	screen.contract.cancel()

	assert_bool(screen.contract.visible).is_false()
	assert_bool(screen.picker.visible).is_true()


func test_only_the_chosen_name_is_highlighted() -> void:
	await _choose(1)

	for i in screen.name_tags.size():
		var highlighted := screen.name_tags[i].modulate.a > 0.9
		assert_bool(highlighted).is_equal(i == 1)


func _click_at(point: Vector2) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = point
	screen._unhandled_input(click)


func test_clicking_a_character_selects_it() -> void:
	var camera := screen.get_viewport().get_camera_3d()
	var target := 3
	var point := camera.unproject_position(screen.models[target].global_position + Vector3.UP * CharacterSelect.BODY_HEIGHT)

	_click_at(point)

	assert_int(screen.picker.selected_index).is_equal(target)


func test_clicking_the_empty_floor_changes_nothing() -> void:
	screen.picker.select(1)

	_click_at(Vector2(5, 5))

	assert_int(screen.picker.selected_index).is_equal(1)


func test_clicks_are_ignored_while_the_contract_is_open() -> void:
	var camera := screen.get_viewport().get_camera_3d()
	screen.picker.select(0)
	screen._offer_contract(screen.picker.selected)

	_click_at(camera.unproject_position(screen.models[2].global_position + Vector3.UP * CharacterSelect.BODY_HEIGHT))

	assert_int(screen.picker.selected_index).is_equal(0)
