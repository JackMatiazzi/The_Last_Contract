class_name Lobby
extends Control
## Contrato em grupo: sala online por código; rede local e túnel em "Outras formas".

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const Network := preload("res://scripts/autoload/net.gd")
const LOCAL_ADDRESS := "127.0.0.1"
const TUNNEL_COMMAND := "cloudflared tunnel --url http://127.0.0.1:%d"
## Na linha de comando (testes e2e), --host, --host=ws ou --host=relay escolhem como hospedar.
const HOST_ARGS := {"--host": Net.Transport.ENET, "--host=ws": Net.Transport.WEBSOCKET, "--host=relay": Net.Transport.RELAY}

@export var address_button_scene: PackedScene

var _pending_choice := Net.NO_CHOICE
var _autostart_players := 0
var _adventurer_buttons: Array[Button] = []

@onready var name_input: LineEdit = %NameInput
@onready var friendly_fire_toggle: CheckButton = %FriendlyFireToggle
@onready var create_online_button: Button = %CreateOnlineButton
@onready var room_code_input: LineEdit = %RoomCodeInput
@onready var join_online_button: Button = %JoinOnlineButton
@onready var other_ways_toggle: Button = %OtherWaysToggle
@onready var other_ways: Control = %OtherWays
@onready var address_input: LineEdit = %AddressInput
## Os ids dos itens são os valores de Net.Transport (rede local e túnel).
@onready var host_mode: OptionButton = %HostMode
@onready var status_label: Label = %StatusLabel
@onready var connect_panel: Control = %ConnectPanel
@onready var room_panel: Control = %RoomPanel
@onready var players_label: Label = %PlayersLabel
@onready var start_button: Button = %StartButton
@onready var group_name_input: LineEdit = %GroupNameInput


func _ready() -> void:
	assert(address_button_scene, "Lobby: aponte address_button_scene")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	create_online_button.pressed.connect(_host_with.bind(Net.Transport.RELAY))
	join_online_button.pressed.connect(_join_online)
	room_code_input.text_changed.connect(_on_room_code_changed)
	other_ways_toggle.toggled.connect(_show_other_ways)
	%HostButton.pressed.connect(func() -> void: _host_with(host_mode.get_selected_id() as Net.Transport))
	%JoinButton.pressed.connect(_join)
	%BackButton.pressed.connect(_back)
	start_button.pressed.connect(Net.start_match)
	friendly_fire_toggle.toggled.connect(Net.set_friendly_fire)
	# o nome vai para os outros quando o host confirma ou sai do campo, nao a cada tecla
	group_name_input.text_submitted.connect(Net.set_group_name)
	group_name_input.focus_exited.connect(func() -> void: Net.set_group_name(group_name_input.text))
	name_input.text = Settings.player_name
	Net.roster_changed.connect(_refresh)
	Net.connection_failed.connect(_on_connection_failed)
	Net.room_ready.connect(_show_room_code)
	multiplayer.connected_to_server.connect(_on_connected)
	var infos := RunState.roster()
	_adventurer_buttons.assign(%Adventurers.get_children())
	for i in _adventurer_buttons.size():
		_adventurer_buttons[i].text = infos[i].title
		_adventurer_buttons[i].pressed.connect(Net.choose_adventurer.bind(i))
	status_label.text = Net.last_error
	Net.last_error = ""
	_show_room(false)
	_apply_command_line()


func _apply_command_line() -> void:
	var args := Net.take_command_line()
	for arg: String in args:
		if arg.begins_with("--adventurer="):
			_pending_choice = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--autostart="):
			_autostart_players = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--name="):
			name_input.text = arg.get_slice("=", 1)
	for arg: String in args:
		if HOST_ARGS.has(arg):
			_host_with(HOST_ARGS[arg])
		elif arg.begins_with("--join"):
			var address := arg.get_slice("=", 1) if "=" in arg else LOCAL_ADDRESS
			if Network.is_room_code(address):
				room_code_input.text = address
				_join_online()
			else:
				address_input.text = address
				_join()


func _show_other_ways(open: bool) -> void:
	other_ways.visible = open
	other_ways_toggle.text = ("▾ " if open else "▸ ") + other_ways_toggle.text.substr(2)


func _on_room_code_changed(text: String) -> void:
	var caret := room_code_input.caret_column
	room_code_input.text = text.to_upper()
	room_code_input.caret_column = caret
	join_online_button.disabled = not Network.is_room_code(room_code_input.text)


func _join_online() -> void:
	address_input.text = room_code_input.text
	_join()


func _host_with(transport: Net.Transport) -> void:
	var error := Net.host(Net.PORT, transport)
	if error != OK:
		status_label.text = "Não foi possível abrir a sala (%s)." % error_string(error)
		return
	match transport:
		Net.Transport.RELAY:
			status_label.text = "Criando a sala online..."
		Net.Transport.WEBSOCKET:
			status_label.text = "Aguardando jogadores."
			_show_tunnel_steps()
		_:
			status_label.text = "Aguardando jogadores."
			_show_host_address()
	Net.set_player_name(name_input.text)
	_show_room(true)
	_choose_pending()


# nao da para saber qual placa os amigos alcancam: cada endereco vira um botao que copia
func _show_host_address() -> void:
	var addresses := Network.shareable_addresses()
	%HostAddress.show()
	if addresses.is_empty():
		%AddressLabel.text = "Sem rede local encontrada. Porta %d." % Net.PORT
		return
	%AddressLabel.text = "Os outros entram com um destes (porta %d). Clique para copiar:" % Net.PORT
	for entry in addresses:
		var button := address_button_scene.instantiate() as Button
		button.text = "%s   (%s)" % [entry.address, entry.label]
		button.pressed.connect(_copy_address.bind(entry.address))
		%AddressButtons.add_child(button)


# o jogo escuta WebSocket na porta; o cloudflared publica essa porta num link https que os outros colam
func _show_tunnel_steps() -> void:
	var command := TUNNEL_COMMAND % Net.PORT
	%HostAddress.show()
	%AddressLabel.text = "Com o cloudflared instalado, rode este comando num terminal e mande para os outros, em particular, o link https://...trycloudflare.com que ele mostrar. Clique para copiar:"
	var button := address_button_scene.instantiate() as Button
	button.text = command
	button.pressed.connect(_copy_address.bind(command))
	%AddressButtons.add_child(button)


func _show_room_code(code: String) -> void:
	status_label.text = "Sala criada. Aguardando jogadores."
	%HostAddress.show()
	%AddressLabel.text = "Os outros entram digitando este código. Clique para copiar:"
	var button := address_button_scene.instantiate() as Button
	button.text = code
	button.pressed.connect(_copy_address.bind(code))
	%AddressButtons.add_child(button)


func _copy_address(address: String) -> void:
	DisplayServer.clipboard_set(address)
	status_label.text = "Copiado: %s" % address


func _join() -> void:
	var address := address_input.text.strip_edges()
	if address.is_empty():
		address = LOCAL_ADDRESS
	var error := Net.join(address)
	if error != OK:
		status_label.text = "Endereço inválido (%s)." % error_string(error)
		return
	status_label.text = "Conectando a %s..." % address
	connect_panel.hide()


func _on_connected() -> void:
	status_label.text = "Conectado. Escolha seu aventureiro."
	Net.set_player_name(name_input.text)
	_show_room(true)
	_choose_pending()


func _on_connection_failed() -> void:
	status_label.text = Net.last_error
	Net.last_error = ""
	_show_room(false)


func _choose_pending() -> void:
	if _pending_choice != Net.NO_CHOICE:
		Net.choose_adventurer(_pending_choice)


func _refresh() -> void:
	var infos := RunState.roster()
	var mine: int = Net.roster.get(multiplayer.get_unique_id(), Net.NO_CHOICE)
	for i in _adventurer_buttons.size():
		_adventurer_buttons[i].disabled = Net.is_taken(i)
		_adventurer_buttons[i].button_pressed = i == mine
	var lines := PackedStringArray()
	for peer_id: int in Net.peers_in_order():
		var choice: int = Net.roster[peer_id]
		var who := Net.display_name(peer_id)
		if peer_id == 1:
			who += " (host)"
		if peer_id == multiplayer.get_unique_id():
			who += " (você)"
		lines.append("%s: %s" % [who, infos[choice].title if choice != Net.NO_CHOICE else "escolhendo..."])
	players_label.text = "\n".join(lines)
	friendly_fire_toggle.disabled = not multiplayer.is_server()
	# so o host escreve; os outros veem o nome que ele escolheu
	group_name_input.editable = multiplayer.is_server()
	if not multiplayer.is_server():
		group_name_input.text = Net.group_name
	friendly_fire_toggle.set_pressed_no_signal(Net.friendly_fire)
	start_button.visible = multiplayer.is_server()
	start_button.disabled = not Net.can_start()
	if _autostart_players > 0 and Net.roster.size() >= _autostart_players and Net.can_start():
		Net.start_match()


func _show_room(in_room: bool) -> void:
	connect_panel.visible = not in_room
	room_panel.visible = in_room
	if in_room:
		_refresh()
	else:
		create_online_button.grab_focus()


func _back() -> void:
	Net.leave()
	get_tree().change_scene_to_file(MAIN_MENU)
