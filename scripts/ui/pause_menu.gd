class_name PauseMenu
extends CanvasLayer

signal resumed
signal abandon_confirmed

const NO_BUFFS := "Nenhuma ainda."

@onready var main_panel: Control = %MainPanel
@onready var guide_panel: Control = %GuidePanel
@onready var confirm_panel: Control = %ConfirmPanel
@onready var settings_menu: SettingsMenu = %SettingsMenu


func _ready() -> void:
	hide()
	%ResumeButton.pressed.connect(close)
	%GuideButton.pressed.connect(_show_panel.bind(guide_panel))
	%GuideBackButton.pressed.connect(_show_panel.bind(main_panel))
	%SettingsButton.pressed.connect(_open_settings)
	%AbandonButton.pressed.connect(_show_panel.bind(confirm_panel))
	%ConfirmAbandonButton.pressed.connect(_abandon_contract)
	%CancelAbandonButton.pressed.connect(_show_panel.bind(main_panel))
	settings_menu.closed.connect(_show_panel.bind(main_panel))


## em grupo o mundo segue rodando para os outros jogadores
func open(objective := "", adventurer: Adventurer = null) -> void:
	get_tree().paused = not Net.is_coop()
	_fill_summary(objective)
	_fill_guide(adventurer)
	show()
	_show_panel(main_panel)


func _fill_summary(objective: String) -> void:
	%AttemptLabel.text = "Tentativa %s · %s" % [Hud.roman(RunState.attempt), RunState.current_adventurer().title]
	%ObjectiveLabel.text = objective
	%ObjectiveLabel.visible = not objective.is_empty()
	%CoopNote.visible = Net.is_coop()
	var lines := RunState.buff_lines()
	%BuffList.text = "\n".join(lines) if not lines.is_empty() else NO_BUFFS


func _fill_guide(adventurer: Adventurer) -> void:
	var info := RunState.current_adventurer()
	%ClassTitle.text = "%s · %s" % [info.title, info.role]
	%ClassDescription.text = info.description
	%AbilityList.text = "\n".join(ability_lines(adventurer)) if adventurer else ""


## uma linha por habilidade com o custo em % da barra, rapido e pesado
static func ability_lines(adventurer: Adventurer) -> PackedStringArray:
	var lines := PackedStringArray()
	var pool := adventurer.attack_pool()
	var source := "mana" if pool == adventurer.mana else "estamina"
	for ability: Attack in adventurer.abilities:
		var quick := roundi(adventurer.cost_of(ability) / pool.maximum * 100.0)
		var heavy := roundi(adventurer.cost_of(ability, true) / pool.maximum * 100.0)
		var cost := "%d%% da %s" % [quick, source] if quick == heavy else "%d%% da %s, pesado %d%%" % [quick, source, heavy]
		lines.append("%s: %s" % [ability.title, cost])
	if adventurer.sustained_attack:
		var spin := roundi(adventurer.cost_of(adventurer.sustained_attack) / pool.maximum * 100.0)
		lines.append("Continue segurando: mais giros, %d%% por volta, andando" % spin)
	var secondary := "Escudo" if adventurer.block else (adventurer.secondary_attack.title if adventurer.secondary_attack else "")
	if not secondary.is_empty():
		lines.append("Botão direito: %s" % secondary)
	return lines


func close() -> void:
	get_tree().paused = false
	hide()
	resumed.emit()


func _unhandled_input(event: InputEvent) -> void:
	var open_panel := main_panel if main_panel.visible else guide_panel if guide_panel.visible else confirm_panel if confirm_panel.visible else null
	if open_panel and get_viewport().gui_get_focus_owner() == null and (event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up")):
		({main_panel: %ResumeButton, guide_panel: %GuideBackButton, confirm_panel: %CancelAbandonButton}[open_panel] as Control).grab_focus()
		get_viewport().set_input_as_handled()
		return
	if not visible or not (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		return
	get_viewport().set_input_as_handled()
	if confirm_panel.visible or guide_panel.visible:
		_show_panel(main_panel)
	else:
		close()


func _open_settings() -> void:
	main_panel.hide()
	settings_menu.open()


func _abandon_contract() -> void:
	get_tree().paused = false
	hide()
	abandon_confirmed.emit()


func _show_panel(panel: Control) -> void:
	main_panel.visible = panel == main_panel
	guide_panel.visible = panel == guide_panel
	confirm_panel.visible = panel == confirm_panel
	if not Settings.uses_gamepad():
		get_viewport().gui_release_focus()
		return
	var focus := {main_panel: %ResumeButton, guide_panel: %GuideBackButton, confirm_panel: %CancelAbandonButton}
	(focus[panel] as Control).grab_focus()
