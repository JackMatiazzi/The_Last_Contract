extends GdUnitTestSuite

# teaser da abertura: toca ao abrir o jogo e cede o lugar ao menu quando acaba ou quando o jogador pula

const TEASER := preload("res://scenes/cutscenes/teaser_intro.tscn")


func _open(teaser_path := "") -> Control:
	var intro: Control = auto_free(TEASER.instantiate())
	intro.next_scene = ""
	if not teaser_path.is_empty():
		intro.teaser_path = teaser_path
	add_child(intro)
	await await_idle_frame()
	return intro


func _press(intro: Control, event: InputEvent) -> void:
	event.pressed = true
	intro._unhandled_input(event)


func test_the_game_opens_on_the_teaser_and_goes_to_the_menu_afterwards() -> void:
	var intro := await _open()

	assert_bool(intro.video.is_playing()).is_true()
	assert_bool(intro.leaving).is_false()
	assert_str(auto_free(TEASER.instantiate()).next_scene).is_equal("res://scenes/ui/main_menu.tscn")
	assert_str(ProjectSettings.get_setting("application/run/main_scene")).is_equal("res://scenes/cutscenes/teaser_intro.tscn")


func test_a_click_a_key_or_a_gamepad_button_skips_the_teaser() -> void:
	for event: InputEvent in [InputEventMouseButton.new(), InputEventKey.new(), InputEventJoypadButton.new()]:
		var intro := await _open()
		if event is InputEventMouseButton:
			event.button_index = MOUSE_BUTTON_LEFT

		_press(intro, event)

		assert_bool(intro.leaving).override_failure_message("%s não pulou o teaser" % event.get_class()).is_true()
		assert_bool(intro.video.is_playing()).is_false()


func test_the_mouse_wheel_does_not_skip() -> void:
	var intro := await _open()
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN

	_press(intro, wheel)

	assert_bool(intro.leaving).is_false()
	assert_bool(intro.video.is_playing()).is_true()


func test_the_end_of_the_video_opens_the_menu() -> void:
	var intro := await _open()

	intro.video.finished.emit()

	assert_bool(intro.leaving).is_true()


func test_without_the_video_it_goes_straight_to_the_menu() -> void:
	var intro := await _open("res://assets/video/nao-existe.ogv")

	assert_bool(intro.video.is_playing()).is_false()
	assert_bool(intro.leaving).is_true()


func test_a_touch_skips_the_teaser() -> void:
	var intro := await _open()

	_press(intro, InputEventScreenTouch.new())

	assert_bool(intro.leaving).is_true()


# só um aperto novo pula: soltar, repetir a tecla segurada ou mexer o mouse não
func test_releases_repeats_and_motion_do_not_skip() -> void:
	var intro := await _open()
	var release := InputEventKey.new()
	release.pressed = false
	var repeat := InputEventKey.new()
	repeat.pressed = true
	repeat.echo = true
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(40, 0)

	for event: InputEvent in [release, repeat, motion]:
		intro._unhandled_input(event)

	assert_bool(intro.leaving).is_false()
	assert_bool(intro.video.is_playing()).is_true()
