class_name Hud
extends CanvasLayer

const ANNOUNCE_HOLD := 3.0
## o chefe nasce longe de quem esta lutando: o aviso fica mais tempo e tem som
const BOSS_ANNOUNCE_HOLD := 5.0
const START_HINT_KEYBOARD := "Esc: pausa e controles"
const START_HINT_GAMEPAD := "Start: pausa e controles"
const ANNOUNCE_FADE := 0.6
const FEED_HOLD := 5.0
const FEED_MAX := 5
const SCORE_HEADERS := 5
const SHORT_FLASH := Color(1.0, 0.35, 0.3)
## exausto: a barra fica apagada ate encher, para o jogador entender por que nao ataca
const EXHAUSTED_TINT := Color(0.45, 0.4, 0.4, 0.75)
## o rastro claro espera um instante e desce ate a vida nova: da para ler quanto o golpe tirou
const TRAIL_DELAY := 0.35
const TRAIL_TIME := 0.4
const ROMAN := [[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]]

@export var player: Character
@export var feed_entry_scene: PackedScene
@export var score_cell_scene: PackedScene
@export var buff_chip_scene: PackedScene
@export var objective_pip_scene: PackedScene

@onready var attempt_label: Label = %AttemptLabel
@onready var health_bar: ProgressBar = %HealthBar
@onready var health_label: Label = %HealthLabel
@onready var health_trail: ProgressBar = %HealthTrail
@onready var stamina_bar: ProgressBar = %StaminaBar
@onready var mana_bar: ProgressBar = %ManaBar
@onready var stamina_ticks: CostTicks = %StaminaTicks
@onready var mana_ticks: CostTicks = %ManaTicks
@onready var ability_icon: TextureRect = %AbilityIcon
@onready var ability_cost: Label = %AbilityCost
@onready var ability_name: Label = %AbilityName
@onready var secondary_slot: Control = %SecondarySlot
@onready var secondary_icon: TextureRect = %SecondaryIcon
@onready var item_icon: TextureRect = %ItemIcon
@onready var item_count: Label = %ItemCount
@onready var item_hint: Label = %ItemHint
@onready var ability_progress: TextureProgressBar = %AbilityProgress
@onready var item_progress: TextureProgressBar = %ItemProgress
@onready var buff_list: HBoxContainer = %BuffList
@onready var crosshair: Control = %Crosshair
@onready var objective_label: Label = %ObjectiveLabel
@onready var pips: HBoxContainer = %Pips
@onready var boss_panel: Control = %BossPanel
@onready var boss_bar: ProgressBar = %BossBar
@onready var announcement: Label = %Announcement
@onready var boss_cue: AudioStreamPlayer = %BossCue
@onready var feed: VBoxContainer = %Feed
@onready var score_layer: CanvasLayer = %ScoreLayer
@onready var score_grid: GridContainer = %ScoreGrid

var _bound_player: Character
var _announce_fade: Tween
var _trail_fall: Tween
var _remaining := -1


func _ready() -> void:
	assert(feed_entry_scene and score_cell_scene and buff_chip_scene and objective_pip_scene, "Hud: aponte as cenas do aviso, do placar, da bênção e do marcador")
	attempt_label.text = "Tentativa %s" % roman(RunState.attempt)
	_show_buffs()
	if player:
		bind(player)
	RunState.feed_posted.connect(_post_feed)
	RunState.stats_changed.connect(_refresh_scoreboard)


func _process(_delta: float) -> void:
	var adventurer := player as Adventurer
	if adventurer:
		ability_progress.value = adventurer.heavy_progress()
		item_progress.value = adventurer.drink_progress()
	var holding := Input.is_action_pressed("scoreboard")
	if holding and not score_layer.visible:
		_refresh_scoreboard()
	score_layer.visible = holding


## ligar duas vezes no mesmo jogador dobraria cada sinal
func bind(new_player: Character) -> void:
	if new_player == _bound_player:
		return
	_bound_player = new_player
	player = new_player
	player.health_changed.connect(_on_health_changed)
	if player.is_node_ready():
		_on_health_changed(player.health, player.get_max_health())
	_bind_energy(player as Adventurer)
	_bind_quickbar(player as Adventurer)


## com remaining, um losango por grupo: aceso enquanto o grupo vive
func set_objective(text: String, remaining := -1, total := 0) -> void:
	objective_label.text = text
	_remaining = remaining
	for pip in pips.get_children():
		pip.free()
	for i in total if remaining >= 0 else 0:
		var pip := objective_pip_scene.instantiate() as Control
		pip.modulate.a = 1.0 if i < remaining else 0.25
		pips.add_child(pip)


func objective_summary() -> String:
	return "%s: %d" % [objective_label.text, _remaining] if _remaining >= 0 else objective_label.text


static func roman(number: int) -> String:
	if number <= 0 or number >= 40:
		return str(number)
	var text := ""
	for pair: Array in ROMAN:
		while number >= pair[0]:
			text += pair[1]
			number -= pair[0]
	return text


func show_boss(boss: Character) -> void:
	boss_panel.show()
	boss_bar.max_value = boss.get_max_health()
	boss_bar.value = boss.health
	boss.health_changed.connect(func(current: float, maximum: float) -> void:
		boss_bar.max_value = maximum
		boss_bar.value = current)
	boss.died.connect(boss_panel.hide)


func announce(text: String, hold := ANNOUNCE_HOLD) -> void:
	announcement.text = text
	if _announce_fade:
		_announce_fade.kill()
	_announce_fade = create_tween()
	_announce_fade.tween_property(announcement, "modulate:a", 1.0, ANNOUNCE_FADE)
	_announce_fade.tween_interval(hold)
	_announce_fade.tween_property(announcement, "modulate:a", 0.0, ANNOUNCE_FADE)


func announce_boss(text: String) -> void:
	announce(text, BOSS_ANNOUNCE_HOLD)
	boss_cue.play()


func show_start_hint() -> void:
	announce(START_HINT_GAMEPAD if Settings.uses_gamepad() else START_HINT_KEYBOARD)


func _bind_energy(adventurer: Adventurer) -> void:
	if adventurer == null:
		return
	_bind_pool(adventurer.stamina, stamina_bar)
	if adventurer.mana:
		_bind_pool(adventurer.mana, mana_bar)
	adventurer.energy_short.connect(func(pool: EnergyPool) -> void:
		_flash(mana_bar if pool == adventurer.mana else stamina_bar))


func _bind_quickbar(adventurer: Adventurer) -> void:
	if adventurer == null:
		return
	adventurer.ability_changed.connect(_show_ability.bind(adventurer))
	adventurer.inventory.changed.connect(_show_item.bind(adventurer))
	_show_ability(adventurer)
	_show_item(adventurer)
	_show_secondary(adventurer)


# o custo aparece em % da barra, e a barra marca um bloco por golpe
func _show_ability(adventurer: Adventurer) -> void:
	var pool := adventurer.attack_pool()
	ability_icon.texture = adventurer.attack.icon
	var step := adventurer.cost_of(adventurer.attack) / pool.maximum
	ability_cost.text = "%d%%" % roundi(step * 100.0)
	stamina_ticks.set_step(step if pool == adventurer.stamina else 0.0)
	mana_ticks.set_step(step if pool == adventurer.mana else 0.0)
	ability_name.text = adventurer.attack.title
	crosshair.visible = adventurer.attack is RangedAttack or adventurer.attack is PortalSpell


func _show_item(adventurer: Adventurer) -> void:
	var item := adventurer.inventory.selected()
	item_icon.texture = item.icon if item else null
	item_count.text = "×%d" % adventurer.inventory.count_of(item) if item else ""
	var hold := "segure X" if Settings.uses_gamepad() else "segure E"
	item_hint.text = "%s\n%s" % [item.title, hold] if item else ""


# sem botao direito (Rogue e Mage) o slot some, mas continua ocupando a celula: a cruz nao muda de lugar
func _show_secondary(adventurer: Adventurer) -> void:
	var icon: Texture2D = null
	if adventurer.block:
		icon = adventurer.block.icon
	elif adventurer.secondary_attack:
		icon = adventurer.secondary_attack.icon
	secondary_icon.texture = icon
	secondary_slot.self_modulate.a = 1.0 if icon else 0.0


func _bind_pool(pool: EnergyPool, bar: ProgressBar) -> void:
	bar.show()
	bar.max_value = pool.maximum
	bar.value = pool.current
	pool.changed.connect(func(current: float, maximum: float) -> void:
		bar.max_value = maximum
		bar.value = current
		bar.self_modulate = EXHAUSTED_TINT if pool.is_exhausted() else Color.WHITE)


func _flash(bar: ProgressBar) -> void:
	bar.modulate = SHORT_FLASH
	bar.create_tween().tween_property(bar, "modulate", Color.WHITE, 0.3)


func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_trail.max_value = maximum
	if _trail_fall:
		_trail_fall.kill()
	if current >= health_trail.value:
		health_trail.value = current
	else:
		_trail_fall = create_tween()
		_trail_fall.tween_interval(TRAIL_DELAY)
		_trail_fall.tween_property(health_trail, "value", current, TRAIL_TIME)
	health_label.text = "%d / %d" % [roundi(current), roundi(maximum)]


## so o nome e os acumulos; o efeito de cada uma fica na pausa
func _show_buffs() -> void:
	var seen: Array[Buff] = []
	for buff in RunState.buffs:
		if buff in seen:
			continue
		seen.append(buff)
		var chip := buff_chip_scene.instantiate() as Label
		var stacks := RunState.stacks_of(buff)
		chip.text = buff.title + (" ×%d" % stacks if stacks > 1 else "")
		buff_list.add_child(chip)


func _post_feed(text: String) -> void:
	var entry := feed_entry_scene.instantiate() as Label
	entry.text = text
	feed.add_child(entry)
	if feed.get_child_count() > FEED_MAX:
		feed.get_child(0).queue_free()
	var fade := entry.create_tween()
	fade.tween_interval(FEED_HOLD)
	fade.tween_property(entry, "modulate:a", 0.0, ANNOUNCE_FADE)
	fade.tween_callback(entry.queue_free)


func _refresh_scoreboard() -> void:
	for cell in score_grid.get_children().slice(SCORE_HEADERS):
		cell.queue_free()
	var peers: Array = Net.peers_in_order() if Net.is_online() else [multiplayer.get_unique_id()]
	for peer_id: int in peers:
		var line := RunState.stats_of(peer_id)
		var you := " (você)" if peer_id == multiplayer.get_unique_id() else ""
		for value in [Net.display_name(peer_id) + you, line.kills, line.assists, line.deaths, line.last_death if line.last_death != "" else "-"]:
			var cell := score_cell_scene.instantiate() as Label
			cell.text = str(value)
			if value is int:
				cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			score_grid.add_child(cell)
