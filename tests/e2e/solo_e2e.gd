extends "res://tests/e2e/e2e_driver.gd"

# um contrato solo do menu ate a segunda tentativa: escolher, assistir, jogar, cair, votar e voltar

const MAGE_INDEX := 2


func run() -> void:
	label = "solo"
	play_with_gamepad()
	if not await skip_teaser_to_menu():
		return
	(get_tree().current_scene.get_node("%PlayButton") as Button).pressed.emit()

	if not await wait_scene("CharacterSelect"):
		return
	var picker := get_tree().current_scene.get_node("%AdventurerPicker") as AdventurerPicker
	picker.select(MAGE_INDEX)
	(picker.get_node("%AcceptButton") as Button).pressed.emit()

	var contract := get_tree().current_scene.get_node("%ContractSign") as ContractSign
	if not await wait_until(func() -> bool: return contract.visible, "contrato para assinar"):
		return
	contract.sign_contract()

	if not await wait_scene("MissionIntro"):
		return
	await skip_cutscene()

	if not await wait_level():
		return
	calm_enemies()
	var game := session()
	check(game.player.scene_file_path.ends_with("mage.tscn"), "o mago escolhido entrou na fase")
	check(game.players.size() == 1, "solo e um grupo de um")
	check(game.player.mana != null and game.player.stamina != null, "mago com mana e estamina")
	check((get_tree().current_scene.get_node("Hud") as Hud).attempt_label.text == "Tentativa I", "HUD mostra a tentativa 1")

	var trigger := InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_LEFT
	trigger.axis_value = 1.0
	Input.parse_input_event(trigger)
	if await wait_until(func() -> bool: return game.player.mana.current < game.player.mana.maximum, "gastar mana no Portal"):
		check(game.player.secondary_attack is PortalSpell and game.player.attack is RangedAttack, "LT inicia o Portal e mantém o projétil no ataque principal")
	var release := InputEventJoypadMotion.new()
	release.axis = JOY_AXIS_TRIGGER_LEFT
	Input.parse_input_event(release)

	game.player.take_damage(999.0)
	await vote_for_first_blessing()
	if not await wait_until(func() -> bool: return RunState.attempt == 2, "segunda tentativa"):
		return
	if not await wait_level():
		return
	check(RunState.buffs.size() == 1, "a bencao escolhida acompanha a nova tentativa")
	check(not session().player.is_dead, "o mago volta vivo")
