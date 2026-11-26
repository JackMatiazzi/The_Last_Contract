class_name SettingsMenu
extends Control

signal closed

const RESTART_NOTE := "Vale ao reiniciar o jogo."
const NEXT_LAUNCH_NOTE := "Vale na próxima vez que abrir o jogo."

## só o menu principal reinicia na hora; na pausa, reiniciar perderia a partida
@export var allows_restart := false

@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SfxSlider
@onready var fullscreen_check: CheckButton = %FullscreenCheck
@onready var vsync_check: CheckButton = %VsyncCheck
@onready var sensitivity_slider: HSlider = %SensitivitySlider
@onready var sensitivity_value: Label = %SensitivityValue
@onready var invert_check: CheckButton = %InvertCheck
@onready var device_option: OptionButton = %DeviceOption
@onready var stick_slider: HSlider = %StickSlider
@onready var stick_value: Label = %StickValue
@onready var graphics_option: OptionButton = %GraphicsOption
@onready var graphics_note: Label = %GraphicsNote
@onready var restart_button: Button = %RestartButton


func _ready() -> void:
	hide()
	_bind_slider(master_slider, &"master_volume")
	_bind_slider(music_slider, &"music_volume")
	_bind_slider(sfx_slider, &"sfx_volume")
	_bind_slider(sensitivity_slider, &"mouse_sensitivity")
	_bind_check(fullscreen_check, &"fullscreen")
	_bind_check(vsync_check, &"vsync")
	_bind_check(invert_check, &"invert_y")
	_bind_slider(stick_slider, &"stick_sensitivity")
	device_option.selected = device_option.get_item_index(Settings.input_device)
	device_option.item_selected.connect(func(index: int) -> void:
		Settings.set_value(&"input_device", device_option.get_item_id(index)))
	_show_multiplier(sensitivity_slider, sensitivity_value)
	_show_multiplier(stick_slider, stick_value)
	%BackButton.pressed.connect(close)
	_bind_telemetry()
	_bind_graphics()


func open() -> void:
	show()
	%Tabs.current_tab = 0
	%BackButton.grab_focus()


func close() -> void:
	hide()
	closed.emit()


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


func _bind_graphics() -> void:
	for node: Control in [%GraphicsLabel, graphics_option, %GraphicsSpacer, %GraphicsStatus]:
		node.visible = Settings.graphics_choice_available()
	graphics_option.selected = graphics_option.get_item_index(Settings.graphics_mode)
	graphics_option.item_selected.connect(func(index: int) -> void:
		Settings.set_value(&"graphics_mode", graphics_option.get_item_id(index))
		_show_graphics_status())
	restart_button.pressed.connect(Settings.restart_game)
	_show_graphics_status()


func _show_graphics_status() -> void:
	var pending := Settings.graphics_restart_needed()
	graphics_note.text = "" if not pending else (RESTART_NOTE if allows_restart else NEXT_LAUNCH_NOTE)
	restart_button.visible = pending and allows_restart


func _bind_telemetry() -> void:
	var check := %TelemetryCheck as CheckButton
	var available := not Playtest.uplink.contact.is_empty()
	check.set_pressed_no_signal(Settings.telemetry_consent == Settings.CONSENT_YES)
	check.disabled = not available
	%DataHint.text = ("Solo: classe, progresso, resultado e outros dados da partida, identificados por um código aleatório, sem seu nome. Sala online: no fim da partida, o apelido e o nome do grupo também vão para o placar. Retenção de 90 dias no Cloudflare, fora do Brasil. Contato: %s" % Playtest.uplink.contact) if available else ""
	%DeleteDataButton.disabled = not available or Settings.player_code.is_empty()
	%DataStatus.text = "" if available else "O envio de dados está desligado nesta versão."
	check.toggled.connect(func(enabled: bool) -> void:
		Settings.accept_telemetry(enabled)
		%DeleteDataButton.disabled = Settings.player_code.is_empty())
	%DeleteDataButton.pressed.connect(_delete_my_data)


func _delete_my_data() -> void:
	%DeleteDataButton.disabled = true
	%DataStatus.text = "Apagando..."
	var deleted: bool = await Playtest.uplink.delete_my_data()
	%DataStatus.text = "Seus dados foram apagados e o envio foi desligado." if deleted else "Não deu para apagar agora. Tente de novo com internet."
	if deleted:
		Settings.accept_telemetry(false)
		Settings.forget_player_code()
		(%TelemetryCheck as CheckButton).set_pressed_no_signal(false)
	else:
		%DeleteDataButton.disabled = false


func _bind_slider(slider: HSlider, key: StringName) -> void:
	slider.value = Settings.get(key)
	slider.value_changed.connect(func(value: float) -> void: Settings.set_value(key, value))


func _bind_check(check: CheckButton, key: StringName) -> void:
	check.button_pressed = Settings.get(key)
	check.toggled.connect(func(pressed: bool) -> void: Settings.set_value(key, pressed))


func _show_multiplier(slider: HSlider, label: Label) -> void:
	var update_label := func(value: float) -> void: label.text = "%.1fx" % value
	slider.value_changed.connect(update_label)
	update_label.call(slider.value)
