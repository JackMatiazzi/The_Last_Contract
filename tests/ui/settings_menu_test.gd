extends GdUnitTestSuite

const MENU := preload("res://scenes/ui/settings_menu.tscn")

var menu: SettingsMenu
const TEST_OVERRIDE := "user://graficos_teste.cfg"

var _device_before: int
var _graphics_before: int


func before_test() -> void:
	_device_before = Settings.input_device
	_graphics_before = Settings.graphics_mode
	Settings.graphics_override_path = TEST_OVERRIDE
	menu = auto_free(MENU.instantiate())
	add_child(menu)
	menu.open()
	await await_idle_frame()


func after_test() -> void:
	Settings.set_value(&"input_device", _device_before)
	Settings.set_value(&"graphics_mode", _graphics_before)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_OVERRIDE))
	Settings.graphics_override_path = Settings.GRAPHICS_OVERRIDE


func _joy_button(button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
	await await_idle_frame()


func test_choosing_controle_switches_to_the_gamepad() -> void:
	var index := menu.device_option.get_item_index(Settings.InputDevice.GAMEPAD)
	menu.device_option.select(index)
	menu.device_option.item_selected.emit(index)

	assert_bool(Settings.uses_gamepad()).is_true()


func test_bumpers_switch_tabs() -> void:
	await _joy_button(JOY_BUTTON_RIGHT_SHOULDER)
	assert_int(menu.get_node("%Tabs").current_tab).is_equal(1)

	await _joy_button(JOY_BUTTON_LEFT_SHOULDER)
	await _joy_button(JOY_BUTTON_LEFT_SHOULDER)
	var tabs := menu.get_node("%Tabs") as TabContainer
	assert_int(tabs.current_tab).is_equal(tabs.get_tab_count() - 1)


func test_b_closes_the_menu() -> void:
	await _joy_button(JOY_BUTTON_B)

	assert_bool(menu.visible).is_false()


func _choose_other_graphics(target: SettingsMenu) -> void:
	var other := Settings.GraphicsMode.QUALITY if RenderingServer.get_current_rendering_method() == "gl_compatibility" else Settings.GraphicsMode.PERFORMANCE
	var index := target.graphics_option.get_item_index(other)
	target.graphics_option.select(index)
	target.graphics_option.item_selected.emit(index)


# na pausa, reiniciar perderia a partida: a troca fica para a próxima vez que o jogo abrir
func test_changing_graphics_during_a_match_waits_for_the_next_launch() -> void:
	_choose_other_graphics(menu)

	assert_str(menu.graphics_note.text).is_equal(SettingsMenu.NEXT_LAUNCH_NOTE)
	assert_bool(menu.restart_button.visible).is_false()


func test_the_main_menu_offers_to_restart_right_away() -> void:
	var main_menu_settings: SettingsMenu = auto_free(MENU.instantiate())
	main_menu_settings.allows_restart = true
	add_child(main_menu_settings)
	await await_idle_frame()

	_choose_other_graphics(main_menu_settings)

	assert_str(main_menu_settings.graphics_note.text).is_equal(SettingsMenu.RESTART_NOTE)
	assert_bool(main_menu_settings.restart_button.visible).is_true()


func test_the_main_menu_settings_allow_restarting() -> void:
	var main_menu: Node = auto_free((load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate())

	assert_bool((main_menu.get_node("%SettingsMenu") as SettingsMenu).allows_restart).is_true()
