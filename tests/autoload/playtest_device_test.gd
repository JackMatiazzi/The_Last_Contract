extends GdUnitTestSuite

# quem joga com controle e quem joga com teclado e mouse: o tempo de cada um vai no fim da partida

var _enabled_before: bool


func before_test() -> void:
	_enabled_before = Playtest.enabled
	Playtest.enabled = true
	Playtest.directory = "user://playtest_device_test"
	Playtest.start_run("Knight", 1, "teste")


func after_test() -> void:
	Playtest._run = {}
	Playtest.enabled = _enabled_before
	Playtest.directory = Playtest.DIR


func _press_gamepad() -> void:
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	button.pressed = true
	Playtest._input(button)


func _press_key() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	Playtest._input(key)


func test_time_after_a_gamepad_button_counts_for_the_gamepad() -> void:
	_press_gamepad()
	Playtest._process(1.0)

	assert_dict(Playtest.device_usage()).is_equal({"device": "controle", "gamepad_share": 1.0})


func test_mixed_play_reports_the_most_used_and_the_gamepad_share() -> void:
	_press_key()
	Playtest._process(1.5)
	_press_gamepad()
	Playtest._process(0.5)

	assert_dict(Playtest.device_usage()).is_equal({"device": "teclado_mouse", "gamepad_share": 0.25})


func test_standing_idle_does_not_count_for_anyone() -> void:
	_press_key()
	Playtest._process(1.0)
	Playtest._last_input_msec -= int((Playtest.IDLE_AFTER + 1.0) * 1000)
	Playtest._process(5.0)

	assert_dict(Playtest.device_usage()).is_equal({"device": "teclado_mouse", "gamepad_share": 0.0})


func test_without_any_input_nothing_is_reported() -> void:
	Playtest._process(3.0)

	assert_dict(Playtest.device_usage()).is_empty()


func test_the_device_reaches_the_server_summary() -> void:
	var run := {"events": [{"type": "victory", "t": 60.0, "attempt": 1, "device": "controle", "gamepad_share": 0.8}]}

	var sent: Dictionary = TelemetryUplink.summary(run).eventos[0]

	assert_str(sent.device).is_equal("controle")
	assert_float(sent.gamepad_share).is_equal(0.8)
