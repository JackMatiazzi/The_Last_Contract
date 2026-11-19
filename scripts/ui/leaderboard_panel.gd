class_name LeaderboardPanel
extends Control
## Placar do menu principal: partidas vencidas em grupo e recordes do solo por classe, vindos da API.
## Cada aba carrega e falha por conta própria; sem internet o jogo segue normal.

signal closed

const ROW := preload("res://scenes/ui/leaderboard_row.tscn")
const LOADING := "Consultando o registro de contratos…"
const OFFLINE := "Não foi possível alcançar o registro. Verifique sua conexão."
const NO_GROUPS := "Nenhum contrato em grupo foi cumprido ainda. Reúna seu grupo e seja o primeiro."
const NO_SOLO := "Ninguém registrou uma vitória solo ainda."
## o nome da classe pede uma primeira coluna mais larga que a da posição no placar de grupos
const CLASS_COLUMN_WIDTH := 110.0

@onready var group_rows: VBoxContainer = %GroupRows
@onready var group_status: Label = %GroupStatus
@onready var solo_rows: VBoxContainer = %SoloRows
@onready var solo_status: Label = %SoloStatus
@onready var retry_button: Button = %RetryButton
@onready var groups_request: HTTPRequest = %GroupsRequest
@onready var solo_request: HTTPRequest = %SoloRequest


func _ready() -> void:
	hide()
	%BackButton.pressed.connect(close)
	retry_button.pressed.connect(refresh)
	groups_request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		show_groups(_answered(result, code), body.get_string_from_utf8()))
	solo_request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		show_solo(_answered(result, code), body.get_string_from_utf8()))


func open() -> void:
	show()
	%Tabs.current_tab = 0
	%BackButton.grab_focus()
	refresh()


func close() -> void:
	groups_request.cancel_request()
	solo_request.cancel_request()
	hide()
	closed.emit()


func refresh() -> void:
	retry_button.hide()
	_show_status(group_status, group_rows, LOADING)
	_show_status(solo_status, solo_rows, LOADING)
	_fetch(groups_request, Leaderboard.GROUPS_PATH, show_groups)
	_fetch(solo_request, Leaderboard.SOLO_PATH, show_solo)


func show_groups(ok: bool, body: String) -> void:
	var rows: Variant = Leaderboard.parse_groups(body) if ok else null
	_fill(group_rows, group_status, rows, NO_GROUPS)


func show_solo(ok: bool, body: String) -> void:
	var rows: Variant = Leaderboard.parse_solo(body) if ok else null
	_fill(solo_rows, solo_status, rows, NO_SOLO, CLASS_COLUMN_WIDTH)
	if rows != null and rows.all(func(row: Array) -> bool: return row[2] == "0"):
		solo_status.text = NO_SOLO
		solo_status.show()


func _fetch(request: HTTPRequest, path: String, on_failure: Callable) -> void:
	request.cancel_request()
	if request.request(Net.api_url(path)) != OK:
		on_failure.call(false, "")


func _fill(rows_box: VBoxContainer, status: Label, rows: Variant, empty_text: String, first_column_width := 0.0) -> void:
	for row in rows_box.get_children():
		row.queue_free()
	if rows == null:
		_show_status(status, rows_box, OFFLINE)
		retry_button.show()
		return
	status.visible = rows.is_empty()
	status.text = empty_text
	for cells: Array in rows:
		var row := ROW.instantiate() as LeaderboardRow
		rows_box.add_child(row)
		row.set_cells(cells)
		if first_column_width > 0.0:
			(row.get_child(0) as Control).custom_minimum_size.x = first_column_width


func _show_status(status: Label, rows_box: VBoxContainer, text: String) -> void:
	for row in rows_box.get_children():
		row.queue_free()
	status.text = text
	status.show()


func _answered(result: int, code: int) -> bool:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_warning("Placar: a API não respondeu (resultado %d, código %d)" % [result, code])
		return false
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
	elif event.is_action_pressed("menu_previous") or event.is_action_pressed("menu_next"):
		var step := -1 if event.is_action_pressed("menu_previous") else 1
		%Tabs.current_tab = wrapi(%Tabs.current_tab + step, 0, %Tabs.get_tab_count())
	else:
		return
	get_viewport().set_input_as_handled()
