class_name TelemetryConsent
extends Control
## Aviso de participação no playtest, mostrado uma vez no menu principal. Nada é enviado antes da
## escolha, e recusar não muda nada no jogo. Dá para mudar depois em Configurações > Dados.

const TEXT := "Ajude a avaliar o jogo: ao fim de cada partida, o jogo envia um resumo (classe, resultado, duração, mortes, bênçãos e onde você caiu) com um código aleatório deste computador, sem o seu nome. No co-op pela sala online, o apelido também vai, como avisa o lobby. Os dados ficam 90 dias em servidores do Cloudflare, fora do Brasil. Você pode desistir ou apagar seus dados em Configurações > Dados. Contato: %s"

signal chosen


func _ready() -> void:
	hide()
	%AcceptButton.pressed.connect(_choose.bind(true))
	%RefuseButton.pressed.connect(_choose.bind(false))


func should_ask() -> bool:
	return Settings.telemetry_consent == Settings.CONSENT_UNSET and not Playtest.uplink.contact.is_empty()


func open() -> void:
	%Body.text = TEXT % Playtest.uplink.contact
	show()
	%AcceptButton.grab_focus()


func _choose(accepted: bool) -> void:
	Settings.accept_telemetry(accepted)
	hide()
	chosen.emit()
