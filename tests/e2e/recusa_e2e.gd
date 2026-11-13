extends "res://tests/e2e/e2e_driver.gd"

# entrar numa sala online que nao existe: o lobby volta para a tela de conexao com o motivo da sala,
# nao fica preso em "conectando". Roda com --join=CODIGO --relay=ws://...


func run() -> void:
	label = "recusa"
	if not await wait_scene("Lobby"):
		return
	var lobby := get_tree().current_scene as Lobby
	if await wait_until(func() -> bool: return lobby.connect_panel.visible and lobby.status_label.text.contains("não encontrada"), "motivo da recusa no lobby"):
		check(true, "lobby mostra que a sala nao existe")
	check(not Net.is_online(), "a conexao recusada foi desfeita")
