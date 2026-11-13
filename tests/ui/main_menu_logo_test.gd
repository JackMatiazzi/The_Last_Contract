extends GdUnitTestSuite


func test_menu_shows_the_seal_before_the_title() -> void:
	var menu: Node = auto_free(load("res://scenes/ui/main_menu.tscn").instantiate())
	var seal := menu.get_node("UI/MenuPanel/Column/Header/Seal") as TextureRect
	var title := menu.get_node("UI/MenuPanel/Column/Header/Title")

	assert_object(seal.texture).is_not_null()
	assert_int(seal.get_index()).is_less(title.get_index())


func test_game_icon_is_the_seal() -> void:
	var icon := load(ProjectSettings.get_setting("application/config/icon")) as Texture2D

	assert_vector(icon.get_size()).is_equal(Vector2(512, 512))
	assert_float(icon.get_image().get_pixel(4, 4).a).is_equal(0.0)


func _menu_in_tree(device: int) -> Node:
	Settings.set_value(&"input_device", device)
	var menu: Node = auto_free(load("res://scenes/ui/main_menu.tscn").instantiate())
	add_child(menu)
	await await_idle_frame()
	return menu


func test_with_the_mouse_no_button_stays_marked_after_settings() -> void:
	var before: int = Settings.input_device
	var menu := await _menu_in_tree(Settings.InputDevice.KEYBOARD_MOUSE)
	menu.get_node("%SettingsButton").grab_focus()
	menu.get_node("%SettingsButton").pressed.emit()

	menu.get_node("%SettingsMenu").closed.emit()

	assert_object(get_viewport().gui_get_focus_owner()).is_null()
	Settings.set_value(&"input_device", before)


func test_with_the_gamepad_focus_returns_to_settings_button() -> void:
	var before: int = Settings.input_device
	var menu := await _menu_in_tree(Settings.InputDevice.GAMEPAD)
	menu.get_node("%SettingsButton").pressed.emit()

	menu.get_node("%SettingsMenu").closed.emit()

	assert_object(get_viewport().gui_get_focus_owner()).is_same(menu.get_node("%SettingsButton"))
	Settings.set_value(&"input_device", before)
