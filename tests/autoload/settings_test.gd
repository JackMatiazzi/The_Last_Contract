extends GdUnitTestSuite

# devolve as preferencias reais do jogador no fim de cada teste

const KEYS := ["master_volume", "music_volume", "sfx_volume", "fullscreen", "vsync", "mouse_sensitivity", "invert_y", "input_device", "stick_sensitivity"]

## gráficos: o teste usa outro arquivo para nunca deixar o jogo do desenvolvedor preso no modo de desempenho
const TEST_OVERRIDE := "user://graficos_teste.cfg"

var _backup := {}
var _graphics_before := 0


func before_test() -> void:
	for key in KEYS:
		_backup[key] = Settings.get(key)
	_graphics_before = Settings.graphics_mode
	Settings.graphics_override_path = TEST_OVERRIDE


# volta o modo de gráficos e o caminho real e apaga o arquivo de teste, mesmo quando um teste falha
func after_test() -> void:
	for key in _backup:
		Settings.set_value(key, _backup[key])
	Settings.set_value(&"graphics_mode", _graphics_before)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_OVERRIDE))
	Settings.graphics_override_path = Settings.GRAPHICS_OVERRIDE


func test_set_value_saves_to_disk() -> void:
	Settings.set_value(&"mouse_sensitivity", 2.5)

	var config := ConfigFile.new()
	assert_int(config.load(Settings.PATH)).is_equal(OK)
	assert_float(config.get_value(Settings.SECTION, "mouse_sensitivity")).is_equal(2.5)


func test_saved_values_come_back_on_next_start() -> void:
	Settings.set_value(&"invert_y", true)

	var next_start: Node = auto_free(load("res://scripts/autoload/settings.gd").new())
	add_child(next_start)

	assert_bool(next_start.invert_y).is_true()


func test_volume_is_applied_to_audio_bus() -> void:
	Settings.set_value(&"music_volume", 0.5)

	var bus := AudioServer.get_bus_index("Music")
	assert_float(AudioServer.get_bus_volume_db(bus)).is_equal_approx(linear_to_db(0.5), 0.01)


func _has_gamepad_event(action: String) -> bool:
	return InputMap.action_get_events(action).any(func(event: InputEvent) -> bool:
		return event is InputEventJoypadButton or event is InputEventJoypadMotion)


func _has_keyboard_or_mouse_event(action: String) -> bool:
	return InputMap.action_get_events(action).any(func(event: InputEvent) -> bool:
		return event is InputEventKey or event is InputEventMouseButton)


func test_gamepad_mode_keeps_only_gamepad_bindings_on_gameplay_actions() -> void:
	Settings.set_value(&"input_device", Settings.InputDevice.GAMEPAD)

	for action in ["move_forward", "run", "attack", "secondary"]:
		assert_bool(_has_gamepad_event(action)).override_failure_message(action).is_true()
		assert_bool(_has_keyboard_or_mouse_event(action)).override_failure_message(action).is_false()


func test_keyboard_mode_gets_its_bindings_back() -> void:
	Settings.set_value(&"input_device", Settings.InputDevice.GAMEPAD)
	Settings.set_value(&"input_device", Settings.InputDevice.KEYBOARD_MOUSE)

	for action in ["move_forward", "run", "attack", "secondary"]:
		assert_bool(_has_keyboard_or_mouse_event(action)).override_failure_message(action).is_true()
		assert_bool(_has_gamepad_event(action)).override_failure_message(action).is_false()


func test_menus_accept_both_devices_in_any_mode() -> void:
	Settings.set_value(&"input_device", Settings.InputDevice.KEYBOARD_MOUSE)

	assert_bool(_has_gamepad_event("pause")).is_true()
	assert_bool(_has_keyboard_or_mouse_event("pause")).is_true()


func test_announces_device_change() -> void:
	Settings.set_value(&"input_device", Settings.InputDevice.KEYBOARD_MOUSE)
	var signals := monitor_signals(Settings, false)

	Settings.set_value(&"input_device", Settings.InputDevice.GAMEPAD)

	await assert_signal(signals).is_emitted("input_device_changed")


func test_automatic_mode_keeps_both_bindings() -> void:
	Settings.set_value(&"input_device", Settings.InputDevice.AUTOMATIC)

	assert_bool(_has_gamepad_event("attack")).is_true()
	assert_bool(_has_keyboard_or_mouse_event("attack")).is_true()


func test_automatic_mode_follows_the_last_device_used() -> void:
	Settings.set_value(&"input_device", Settings.InputDevice.AUTOMATIC)
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	button.pressed = true
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true

	Input.parse_input_event(button)
	await await_idle_frame()
	assert_bool(Settings.uses_gamepad()).is_true()

	Input.parse_input_event(key)
	await await_idle_frame()
	assert_bool(Settings.uses_gamepad()).is_false()

	button.pressed = false
	Input.parse_input_event(button)
	key.pressed = false
	Input.parse_input_event(key)


func test_automatic_mode_ignores_a_shaky_mouse() -> void:
	Settings.set_value(&"input_device", Settings.InputDevice.AUTOMATIC)
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 1.0
	var jitter := InputEventMouseMotion.new()
	jitter.relative = Vector2(1, 1)
	jitter.screen_relative = Vector2(1, 1)

	Input.parse_input_event(stick)
	Input.parse_input_event(jitter)
	await await_idle_frame()

	assert_bool(Settings.uses_gamepad()).is_true()
	stick.axis_value = 0.0
	Input.parse_input_event(stick)


func test_a_fresh_install_starts_on_keyboard_and_mouse() -> void:
	var fresh: Node = auto_free(load("res://scripts/autoload/settings.gd").new())

	assert_int(fresh.input_device).is_equal(Settings.InputDevice.KEYBOARD_MOUSE)


func test_the_game_reads_the_graphics_file_before_opening_the_window() -> void:
	assert_str(ProjectSettings.get_setting("application/config/project_settings_override")).is_equal(Settings.GRAPHICS_OVERRIDE)


func test_performance_saves_the_light_renderer_and_quality_removes_it() -> void:
	Settings.set_value(&"graphics_mode", Settings.GraphicsMode.PERFORMANCE)
	var config := ConfigFile.new()
	assert_int(config.load(TEST_OVERRIDE)).is_equal(OK)
	assert_str(config.get_value("rendering", "renderer/rendering_method")).is_equal("gl_compatibility")

	Settings.set_value(&"graphics_mode", Settings.GraphicsMode.QUALITY)
	assert_bool(FileAccess.file_exists(TEST_OVERRIDE)).is_false()


func test_the_graphics_choice_is_saved_with_the_other_settings() -> void:
	Settings.set_value(&"graphics_mode", Settings.GraphicsMode.PERFORMANCE)

	var config := ConfigFile.new()
	config.load(Settings.PATH)
	assert_int(config.get_value(Settings.SECTION, "graphics_mode")).is_equal(Settings.GraphicsMode.PERFORMANCE)


func test_a_restart_is_needed_only_when_the_choice_differs_from_the_running_renderer() -> void:
	var running := Settings.GraphicsMode.PERFORMANCE if RenderingServer.get_current_rendering_method() == "gl_compatibility" else Settings.GraphicsMode.QUALITY
	var other := Settings.GraphicsMode.QUALITY if running == Settings.GraphicsMode.PERFORMANCE else Settings.GraphicsMode.PERFORMANCE

	Settings.set_value(&"graphics_mode", running)
	assert_bool(Settings.graphics_restart_needed()).is_false()
	Settings.set_value(&"graphics_mode", other)
	assert_bool(Settings.graphics_restart_needed()).is_true()


# o settings.cfg manda: ao abrir, um arquivo de gráficos que sobrou de outra escolha é apagado
func test_opening_the_game_removes_a_leftover_graphics_file() -> void:
	Settings.set_value(&"graphics_mode", Settings.GraphicsMode.QUALITY)
	var leftover := ConfigFile.new()
	leftover.set_value("rendering", "renderer/rendering_method", "gl_compatibility")
	leftover.save(TEST_OVERRIDE)

	Settings._ready()

	assert_bool(FileAccess.file_exists(TEST_OVERRIDE)).is_false()
