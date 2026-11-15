extends "res://tests/e2e/e2e_driver.gd"

# do chefe morto ao calabouço apertando E no alçapão, como o jogador faz; troca de cena no meio da tecla
# não pode deixar nó fora da árvore lendo posição nem viewport

const KNIGHT_INDEX := 0


func run() -> void:
	label = "alcapao"
	play_with_gamepad()
	if not await wait_scene("MainMenu"):
		return
	(get_tree().current_scene.get_node("%PlayButton") as Button).pressed.emit()
	if not await wait_scene("CharacterSelect"):
		return
	var picker := get_tree().current_scene.get_node("%AdventurerPicker") as AdventurerPicker
	picker.select(KNIGHT_INDEX)
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
	var spot := game.player.global_position + Vector3(1.5, 0, 0)
	game.open_trapdoor_at(spot)
	if not await wait_until(func() -> bool: return game.player.interactables_in_reach > 0, "aviso do alçapão ao chegar perto"):
		return
	press_action(&"interact")
	if not await wait_scene("CalaboucoEscondidoLevel"):
		return
	check(true, "apertar E no alçapão leva ao calabouço")
	if not await wait_until(func() -> bool: return not Net.waiting_for_peers and get_tree().current_scene.has_node("GameSession"), "calabouço carregado"):
		return
	check(not session().player.is_dead, "o grupo começa vivo na entrada do calabouço")
