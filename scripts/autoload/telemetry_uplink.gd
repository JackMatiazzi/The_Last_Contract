class_name TelemetryUplink
extends Node
## Envia o resumo do playtest à API da sala online, só para quem aceitou participar.
## Solo: abre uma sessão no começo, manda o resumo a cada marco e fecha no fim; quem fecha o jogo no
## meio ainda deixa o caminho até ali. Co-op: um relatório no fim, com a ficha que a sala deu.
## Os envios saem um de cada vez, na ordem: o fechamento nunca chega antes do marco anterior.
## Se a rede falhar, o jogo segue normalmente e o arquivo local do playtest continua sendo gravado.

## rodada de playtest desta build; precisa estar na lista RODADAS da API
const ROUND := "PLAYTEST-NOV-2026"
## contato que aparece no aviso de participação. Vazio = nada é enviado e o aviso não aparece
## (a LGPD pede um contato real antes de coletar). Preencher antes de gerar a build do playtest
const CONTACT := ""
## estes eventos disparam um envio parcial no solo
const MILESTONES: Array[String] = ["group_cleared", "boss_killed", "blessing_chosen", "trapdoor_entered", "trapdoor_expired", "dungeon_entered", "dungeon_exit"]
## campos que a API aceita em cada evento; o resto (como o resumo de dano) fica só no arquivo local
const FIELDS: Array[String] = ["type", "t", "attempt", "position", "buff", "buffs", "enemy", "stage", "groups_left", "hits", "taken", "healed", "device", "gamepad_share"]
## a API recusa eventos acima de 16 KB; com folga, numa partida longa saem primeiro as mortes mais antigas
const MAX_EVENT_BYTES := 12000
## ao fechar o jogo, espera no máximo isso pelo último envio
const QUIT_WAIT_SECONDS := 2.0
const COOP_PATH := "/telemetria"
const FRIENDLY_FIRE := "Fogo amigo"

signal sent(path: String, accepted: bool)

var contact := CONTACT
var session := ""
## só nos testes ponta a ponta: aceite e código que valem nesta execução e nunca vão para as configurações
var test_code := ""
var _queue: Array[Dictionary] = []
var _in_flight := false
## cada partida solo tem um número: resposta atrasada de uma partida antiga não mexe na atual
var _run_id := 0
## o fechamento chegou antes da sessão abrir: sai assim que ela abrir
var _queued_final := {}


func is_active() -> bool:
	return (Settings.telemetry_consent == Settings.CONSENT_YES or not test_code.is_empty()) and not contact.is_empty()


func player_code() -> String:
	return test_code if not test_code.is_empty() else Settings.player_code


## o resumo que vai ao servidor, igual no solo e no co-op
static func summary(run: Dictionary) -> Dictionary:
	var events: Array = run.get("events", [])
	return {
		"classe": run.get("adventurer", ""),
		"versao": run.get("version", ""),
		"tentativas": maxi(RunState.attempt, 1),
		"mortes": events.filter(func(event: Dictionary) -> bool: return event.type == "player_died").size(),
		"minutos": snappedf(float(run.get("duration", 0.0)) / 60.0, 0.1),
		"achou_bonus": events.any(func(event: Dictionary) -> bool: return event.type == "trapdoor_entered"),
		"eventos": fit_events(events),
	}


## os marcos da partida (tentativas, grupos, chefe, alçapão, calabouço, fim) vão sempre; as outras
## linhas, como as mortes, entram das mais novas para as mais antigas até o limite de tamanho
static func fit_events(events: Array) -> Array:
	var cleaned: Array = events.map(_clean_event)
	var keep: Array[bool] = []
	var size := 0
	for event: Dictionary in cleaned:
		var always: bool = event.type != "player_died"
		keep.append(always)
		if always:
			size += JSON.stringify(event).length() + 1
	for i in range(cleaned.size() - 1, -1, -1):
		if keep[i]:
			continue
		var length := JSON.stringify(cleaned[i]).length() + 1
		if size + length > MAX_EVENT_BYTES:
			break
		keep[i] = true
		size += length
	var fitted: Array = []
	for i in cleaned.size():
		if keep[i]:
			fitted.append(cleaned[i])
	return fitted


static func _clean_event(event: Dictionary) -> Dictionary:
	var clean := {}
	for field in FIELDS:
		if event.has(field):
			clean[field] = event[field]
	if clean.has("enemy"):
		clean.enemy = without_player_name(str(clean.enemy))
	if clean.has("hits"):
		clean.hits = clean.hits.map(func(hit: Array) -> Array: return [without_player_name(str(hit[0])), hit[1]])
	return clean


## o golpe de um aliado vem com o apelido dele ("Fogo amigo de Ana"); para o servidor vai só "Fogo amigo"
static func without_player_name(source: String) -> String:
	return FRIENDLY_FIRE if source.begins_with(FRIENDLY_FIRE) else source


func open_solo(run: Dictionary) -> void:
	_run_id += 1
	session = ""
	_queued_final = {}
	if not is_active():
		return
	var body := {"rodada": ROUND, "versao": run.get("version", ""), "classe": run.get("adventurer", ""), "jogador": player_code()}
	_enqueue("/solo/inicio", body, _on_session_opened.bind(_run_id))


func milestone(run: Dictionary) -> void:
	if is_active() and not session.is_empty():
		_enqueue("/solo/marco", summary(run).merged({"sessao": session}))


func close_solo(run: Dictionary, result: String) -> void:
	if not is_active():
		return
	var body := summary(run).merged({"final": true, "resultado": result})
	if session.is_empty():
		_queued_final = body
		return
	_enqueue("/solo/marco", body.merged({"sessao": session}))
	session = ""


## co-op: só sai se a partida foi pela sala online (é ela que deu a ficha); entra na mesma fila, para
## fechar o jogo também esperar por ele
func send_coop(run: Dictionary, result: String) -> void:
	if not is_active():
		return
	var report := Net.take_match_report(summary(run).merged({"resultado": result, "jogador": player_code(), "grupo": Net.group_name}))
	if not report.is_empty():
		_enqueue(COOP_PATH, report)


## apaga no servidor tudo que o código deste PC gerou (solo e co-op); devolve se conseguiu
func delete_my_data() -> bool:
	if Settings.player_code.is_empty():
		return true
	var request := HTTPRequest.new()
	request.timeout = 10.0
	add_child(request)
	if request.request(Net.api_url("/jogador/" + Settings.player_code), [], HTTPClient.METHOD_DELETE) != OK:
		request.queue_free()
		return false
	var answer: Array = await request.request_completed
	request.queue_free()
	return answer[0] == HTTPRequest.RESULT_SUCCESS and answer[1] == 200


func is_idle() -> bool:
	return _queue.is_empty() and not _in_flight


func wait_until_idle(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + seconds * 1000.0
	while not is_idle() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _on_session_opened(accepted: bool, answer: Variant, run_id: int) -> void:
	if run_id != _run_id or not accepted or not answer is Dictionary:
		return
	session = str(answer.get("sessao", ""))
	if not _queued_final.is_empty():
		_enqueue("/solo/marco", _queued_final.merged({"sessao": session}))
		_queued_final = {}
		session = ""


func _enqueue(path: String, body: Dictionary, on_answer := Callable()) -> void:
	_queue.append({"path": path, "body": body, "on_answer": on_answer})
	_send_next()


func _send_next() -> void:
	if _in_flight or _queue.is_empty():
		return
	var next: Dictionary = _queue.pop_front()
	var request := HTTPRequest.new()
	request.timeout = 10.0
	add_child(request)
	request.request_completed.connect(_on_answered.bind(request, next.path, next.on_answer))
	var url := Net.api_url(str(next.path))
	if request.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(next.body)) != OK:
		request.queue_free()
		_send_next()
		return
	_in_flight = true


func _on_answered(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, path: String, on_answer: Callable) -> void:
	_in_flight = false
	request.queue_free()
	var accepted := result == HTTPRequest.RESULT_SUCCESS and code == 200
	if not accepted:
		push_warning("Playtest: envio %s não foi aceito (resultado %d, http %d)" % [path, result, code])
	if on_answer.is_valid():
		on_answer.call(accepted, JSON.parse_string(body.get_string_from_utf8()))
	sent.emit(path, accepted)
	if path == COOP_PATH:
		Net.match_report_sent.emit(accepted)
	_send_next()
