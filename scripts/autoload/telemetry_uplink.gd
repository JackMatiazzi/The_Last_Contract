class_name TelemetryUplink
extends Node
## Envia o resumo do playtest à API da sala online, só para quem aceitou participar.
## Solo: abre uma sessão no começo, manda o resumo a cada marco e fecha no fim; quem fecha o jogo no
## meio ainda deixa o caminho até ali. Co-op: um relatório no fim, com a ficha que a sala deu.
## Se a rede falhar, o jogo segue normalmente e o arquivo local do playtest continua sendo gravado.

## rodada de playtest desta build; precisa estar na lista RODADAS da API
const ROUND := "PLAYTEST-NOV-2026"
## contato que aparece no aviso de participação. Vazio = nada é enviado e o aviso não aparece
## (a LGPD pede um contato real antes de coletar). Preencher antes de gerar a build do playtest
const CONTACT := ""
## estes eventos disparam um envio parcial no solo
const MILESTONES: Array[String] = ["group_cleared", "boss_killed", "blessing_chosen", "trapdoor_entered", "trapdoor_expired", "dungeon_entered", "dungeon_exit"]
## campos que a API aceita em cada evento; o resto (como o resumo de dano) fica só no arquivo local
const FIELDS: Array[String] = ["type", "t", "attempt", "position", "buff", "enemy", "stage", "groups_left", "hits", "taken", "healed"]
## a API recusa resumo acima de 16 KB: numa partida longa vão os eventos mais recentes
const MAX_EVENTS := 150
## ao fechar o jogo, espera no máximo isso pelo último envio
const QUIT_WAIT_SECONDS := 2.0

signal sent(path: String, accepted: bool)

var contact := CONTACT
var session := ""
## so nos testes ponta a ponta: aceite e codigo que valem nesta execucao e nunca vao para as configuracoes
var test_code := ""
var _pending := 0
## o fechamento chegou antes da sessão abrir: manda assim que ela abrir
var _queued_final := {}


func is_active() -> bool:
	return (Settings.telemetry_consent == Settings.CONSENT_YES or not test_code.is_empty()) and not contact.is_empty()


func player_code() -> String:
	return test_code if not test_code.is_empty() else Settings.player_code


## o resumo que vai ao servidor, igual no solo e no co-op
static func summary(run: Dictionary) -> Dictionary:
	var events: Array = run.get("events", [])
	var kept: Array = []
	for event: Dictionary in events.slice(maxi(events.size() - MAX_EVENTS, 0)):
		var clean := {}
		for field in FIELDS:
			if event.has(field):
				clean[field] = event[field]
		kept.append(clean)
	return {
		"classe": run.get("adventurer", ""),
		"versao": run.get("version", ""),
		"tentativas": maxi(RunState.attempt, 1),
		"mortes": events.filter(func(event: Dictionary) -> bool: return event.type == "player_died").size(),
		"achou_bonus": events.any(func(event: Dictionary) -> bool: return event.type == "trapdoor_entered"),
		"eventos": kept,
	}


func open_solo(run: Dictionary) -> void:
	session = ""
	_queued_final = {}
	if not is_active():
		return
	var body := {"rodada": ROUND, "versao": run.get("version", ""), "classe": run.get("adventurer", ""), "jogador": player_code()}
	_post("/solo/inicio", body, _on_session_opened)


func milestone(run: Dictionary) -> void:
	if is_active() and not session.is_empty():
		_post("/solo/marco", summary(run).merged({"sessao": session}), Callable())


func close_solo(run: Dictionary, result: String) -> void:
	if not is_active():
		return
	var body := summary(run).merged({"final": true, "resultado": result})
	if session.is_empty():
		_queued_final = body
		return
	_post("/solo/marco", body.merged({"sessao": session}), Callable())
	session = ""


## co-op: só sai se a partida foi pela sala online (é ela que deu a ficha)
func send_coop(run: Dictionary, result: String) -> void:
	if is_active():
		Net.send_match_report(summary(run).merged({"resultado": result, "jogador": player_code(), "grupo": Net.group_name}))


## apaga no servidor tudo que o código deste PC gerou (solo e co-op); devolve se conseguiu
func delete_my_data() -> bool:
	if Settings.player_code.is_empty():
		return true
	var request := HTTPRequest.new()
	request.timeout = 10.0
	add_child(request)
	if request.request(Net.http_address(Net.relay_url) + "/jogador/" + Settings.player_code, [], HTTPClient.METHOD_DELETE) != OK:
		request.queue_free()
		return false
	var answer: Array = await request.request_completed
	request.queue_free()
	return answer[0] == HTTPRequest.RESULT_SUCCESS and answer[1] == 200


func is_idle() -> bool:
	return _pending == 0


func wait_until_idle(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + seconds * 1000.0
	while _pending > 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _on_session_opened(accepted: bool, answer: Variant) -> void:
	if not accepted or not answer is Dictionary:
		return
	session = str(answer.get("sessao", ""))
	if not _queued_final.is_empty():
		_post("/solo/marco", _queued_final.merged({"sessao": session}), Callable())
		_queued_final = {}
		session = ""


func _post(path: String, body: Dictionary, on_answer: Callable) -> void:
	var request := HTTPRequest.new()
	request.timeout = 10.0
	add_child(request)
	request.request_completed.connect(_on_answered.bind(request, path, on_answer))
	var url := Net.http_address(Net.relay_url) + path
	if request.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		request.queue_free()
		return
	_pending += 1


func _on_answered(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, path: String, on_answer: Callable) -> void:
	_pending -= 1
	request.queue_free()
	var accepted := result == HTTPRequest.RESULT_SUCCESS and code == 200
	if not accepted:
		push_warning("Playtest: envio %s não foi aceito (resultado %d, http %d)" % [path, result, code])
	if on_answer.is_valid():
		on_answer.call(accepted, JSON.parse_string(body.get_string_from_utf8()))
	sent.emit(path, accepted)
