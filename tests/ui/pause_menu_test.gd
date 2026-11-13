extends GdUnitTestSuite

const PAUSE_MENU := preload("res://scenes/ui/pause_menu.tscn")

var arena: TestArena
var pause: PauseMenu


func before_test() -> void:
	arena = TestArena.new(self)
	pause = PAUSE_MENU.instantiate()
	arena.root.add_child(pause)
	await arena.wait_physics(1)


func after_test() -> void:
	get_tree().paused = false


func test_open_pauses_the_game() -> void:
	pause.open()

	assert_bool(get_tree().paused).is_true()
	assert_bool(pause.main_panel.visible).is_true()


func test_close_resumes_and_emits_resumed() -> void:
	var signals := monitor_signals(pause, false)
	pause.open()

	pause.close()

	assert_bool(get_tree().paused).is_false()
	await assert_signal(signals).is_emitted("resumed")


func test_esc_inside_settings_returns_to_pause_panel() -> void:
	pause.open()
	pause.get_node("%SettingsButton").pressed.emit()
	assert_bool(pause.settings_menu.visible).is_true()

	await arena.send_action("pause")

	assert_bool(pause.settings_menu.visible).is_false()
	assert_bool(pause.main_panel.visible).is_true()
	assert_bool(get_tree().paused).is_true()


func test_abandon_requires_confirmation() -> void:
	pause.open()

	pause.get_node("%AbandonButton").pressed.emit()

	assert_bool(pause.confirm_panel.visible).is_true()
	assert_bool(pause.visible).is_true()
	assert_bool(get_tree().paused).is_true()


func test_esc_on_confirmation_cancels_abandon() -> void:
	pause.open()
	pause.get_node("%AbandonButton").pressed.emit()

	await arena.send_action("pause")

	assert_bool(pause.main_panel.visible).is_true()
	assert_bool(get_tree().paused).is_true()


func test_confirming_abandon_unpauses_and_emits() -> void:
	var signals := monitor_signals(pause, false)
	pause.open()
	pause.get_node("%AbandonButton").pressed.emit()

	pause.get_node("%ConfirmAbandonButton").pressed.emit()

	assert_bool(get_tree().paused).is_false()
	await assert_signal(signals).is_emitted("abandon_confirmed")


func test_summary_shows_attempt_adventurer_and_objective() -> void:
	RunState.reset()
	RunState.attempt = 3

	pause.open("Grupos restantes: 2")

	assert_str(pause.get_node("%AttemptLabel").text).contains("Tentativa III").contains(RunState.current_adventurer().title)
	assert_str(pause.get_node("%ObjectiveLabel").text).contains("Grupos restantes: 2")


func test_summary_lists_each_blessing_once_with_its_effect() -> void:
	RunState.reset()
	var blade: Buff = load("res://resources/buffs/lamina_afiada.tres")
	RunState.buffs.append(blade)
	RunState.buffs.append(blade)

	pause.open()

	var text: String = pause.get_node("%BuffList").text
	assert_str(text).contains(blade.title).contains("×2").contains(blade.describe().split("\n")[0])
	assert_int(text.count(blade.title)).is_equal(1)
	RunState.reset()


func test_summary_without_blessings_says_how_they_come() -> void:
	RunState.reset()

	pause.open()

	assert_str(pause.get_node("%BuffList").text).is_equal(PauseMenu.NO_BUFFS)
	assert_bool(pause.get_node("%CoopNote").visible).is_false()
	assert_bool(pause.get_node("%ObjectiveLabel").visible).is_false()


func test_guide_explains_controls_and_the_class_abilities() -> void:
	RunState.reset()
	var knight := arena.spawn(TestArena.KNIGHT, Vector3(4, 0, 0)) as Adventurer
	await arena.wait_physics(2)
	pause.open("", knight)

	pause.get_node("%GuideButton").pressed.emit()

	assert_bool(pause.guide_panel.visible).is_true()
	assert_bool(pause.main_panel.visible).is_false()
	assert_str(pause.get_node("%ClassTitle").text).contains(RunState.current_adventurer().title)
	var cost := roundi(knight.cost_of(knight.attack) / knight.stamina.maximum * 100.0)
	assert_str(pause.get_node("%AbilityList").text).contains("%s: %d%% da estamina" % [knight.attack.title, cost]).contains("Botão direito: Escudo")


func test_mage_abilities_are_paid_in_mana_and_have_no_right_button() -> void:
	var mage := arena.spawn(TestArena.MAGE, Vector3(4, 0, 0)) as Adventurer
	await arena.wait_physics(2)

	var lines := PauseMenu.ability_lines(mage)

	assert_int(lines.size()).is_equal(mage.abilities.size())
	for line in lines:
		assert_str(line).contains("da mana")
	assert_str("\n".join(lines)).not_contains("Botão direito")


func test_esc_on_the_guide_goes_back_to_the_pause() -> void:
	pause.open()
	pause.get_node("%GuideButton").pressed.emit()

	await arena.send_action("pause")

	assert_bool(pause.main_panel.visible).is_true()
	assert_bool(pause.guide_panel.visible).is_false()
	assert_bool(get_tree().paused).is_true()
