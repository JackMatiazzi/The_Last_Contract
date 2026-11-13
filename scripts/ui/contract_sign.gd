class_name ContractSign
extends CanvasLayer
## O contrato do Lorde antes da missao: o nome assinado vira o nome do jogador no jogo.

signal signed(signature: String)
signal cancelled

@onready var name_input: LineEdit = %NameInput
@onready var signature: Label = %Signature
@onready var trade_label: Label = %TradeLabel


func _ready() -> void:
	hide()
	name_input.max_length = Net.MAX_NAME_LENGTH
	name_input.text_changed.connect(_preview)
	name_input.text_submitted.connect(func(_text: String) -> void: sign_contract())
	%SignButton.pressed.connect(sign_contract)
	%BackButton.pressed.connect(cancel)


# quem nunca assinou encontra a linha em branco; quem ja assinou so confirma (bom para o controle)
func open(info: AdventurerInfo) -> void:
	trade_label.text = "Ofício: %s" % info.title
	var last := Settings.player_name
	name_input.text = "" if last == Settings.DEFAULT_PLAYER_NAME else last
	_preview(name_input.text)
	show()
	if name_input.text.is_empty():
		name_input.grab_focus()
	else:
		%SignButton.grab_focus()


func sign_contract() -> void:
	if not visible:
		return
	Net.set_player_name(name_input.text)
	hide()
	signed.emit(Settings.player_name)


func cancel() -> void:
	hide()
	cancelled.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		cancel()


func _preview(text: String) -> void:
	signature.text = Net.clean_name(text)
