extends "res://tests/e2e/e2e_driver.gd"

# do menu até a terceira tentativa: a cada 2 tentativas jogadas o aventureiro volta com 1 de vida máxima a mais.
# Com janela (sem --headless) dá para assistir; --segurar=N deixa a última tela aberta por N segundos

const KNIGHT_INDEX := 0


func run() -> void:
	label = "vida-extra"
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

	for attempt in [1, 2, 3]:
		if not await wait_until(func() -> bool: return RunState.attempt == attempt, "tentativa %d" % attempt):
			return
		if not await wait_level():
			return
		calm_enemies()
		var knight := session().player
		var expected := maxf(knight.max_health + knight.get_stat_bonus(StatModifier.Stat.MAX_HEALTH), 1.0) + (1.0 if attempt == 3 else 0.0)
		check(is_equal_approx(knight.get_max_health(), expected), "tentativa %d: vida máxima %.0f (esperado %.0f)" % [attempt, knight.get_max_health(), expected])
		check(is_equal_approx(knight.health, knight.get_max_health()), "tentativa %d: começa com a vida cheia" % attempt)
		print("E2E vida-extra: tentativa %d, vida %.0f / %.0f" % [attempt, knight.health, knight.get_max_health()])
		await get_tree().create_timer(2.0).timeout
		if attempt < 3:
			knight.take_damage(999.0)
			await vote_for_first_blessing()
	await get_tree().create_timer(_hold_seconds()).timeout


func _hold_seconds() -> float:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--segurar="):
			return arg.trim_prefix("--segurar=").to_float()
	return 0.0
