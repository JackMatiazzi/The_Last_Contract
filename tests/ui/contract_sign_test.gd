extends GdUnitTestSuite

# devolve o nome real do jogador no fim de cada teste

const CONTRACT_SIGN := preload("res://scenes/ui/contract_sign.tscn")
const KNIGHT := preload("res://resources/adventurers/knight.tres")

var sheet: ContractSign
var _saved_name := ""


func before_test() -> void:
	_saved_name = Settings.player_name
	sheet = auto_free(CONTRACT_SIGN.instantiate())
	add_child(sheet)
	await await_idle_frame()


func after_test() -> void:
	Settings.set_value(&"player_name", _saved_name)


func test_starts_hidden() -> void:
	assert_bool(sheet.visible).is_false()


func test_opens_with_the_last_signed_name() -> void:
	Settings.set_value(&"player_name", "Ana")

	sheet.open(KNIGHT)

	assert_bool(sheet.visible).is_true()
	assert_str(sheet.name_input.text).is_equal("Ana")


func test_default_name_leaves_the_line_blank_to_write() -> void:
	Settings.set_value(&"player_name", Settings.DEFAULT_PLAYER_NAME)

	sheet.open(KNIGHT)

	assert_str(sheet.name_input.text).is_empty()


func test_shows_the_chosen_trade() -> void:
	sheet.open(KNIGHT)

	assert_str(sheet.trade_label.text).contains(KNIGHT.title)


func test_signature_follows_what_is_typed() -> void:
	sheet.open(KNIGHT)

	sheet.name_input.text = "Bia"
	sheet.name_input.text_changed.emit("Bia")

	assert_str(sheet.signature.text).is_equal("Bia")


func test_signing_saves_the_cleaned_name_and_reports_it() -> void:
	sheet.open(KNIGHT)
	# espacos nas pontas e um caractere invisivel de largura zero no fim
	sheet.name_input.text = "  Caio" + char(0x200b) + " "
	var signals := monitor_signals(sheet)

	sheet.sign_contract()

	assert_str(Settings.player_name).is_equal("Caio")
	assert_bool(sheet.visible).is_false()
	await assert_signal(signals).is_emitted("signed", ["Caio"])


func test_blank_signature_signs_as_aventureiro() -> void:
	sheet.open(KNIGHT)
	sheet.name_input.text = "   "

	sheet.sign_contract()

	assert_str(Settings.player_name).is_equal(Settings.DEFAULT_PLAYER_NAME)


func test_enter_on_the_line_signs() -> void:
	sheet.open(KNIGHT)
	sheet.name_input.text = "Bia"
	var signals := monitor_signals(sheet)

	sheet.name_input.text_submitted.emit("Bia")

	await assert_signal(signals).is_emitted("signed", ["Bia"])


func test_signing_twice_reports_only_once() -> void:
	sheet.open(KNIGHT)
	var count := [0]
	sheet.signed.connect(func(_signature: String) -> void: count[0] += 1)

	sheet.sign_contract()
	sheet.sign_contract()

	assert_int(count[0]).is_equal(1)


func test_esc_goes_back() -> void:
	sheet.open(KNIGHT)
	var signals := monitor_signals(sheet)

	await _press("ui_cancel")

	assert_bool(sheet.visible).is_false()
	await assert_signal(signals).is_emitted("cancelled")


func test_going_back_hides_without_signing() -> void:
	Settings.set_value(&"player_name", "Ana")
	sheet.open(KNIGHT)
	sheet.name_input.text = "Outro"
	var signals := monitor_signals(sheet)

	sheet.cancel()

	assert_bool(sheet.visible).is_false()
	assert_str(Settings.player_name).is_equal("Ana")
	await assert_signal(signals).is_emitted("cancelled")


# solta a tecla no fim para o proximo teste nao herdar a acao apertada
func _press(action: String) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
