class_name Adventurer
extends Character

signal energy_short(pool: EnergyPool)
signal ability_changed
signal potion_used(text: String)

## vida de referência do dano dos inimigos: o dano deles é escrito pensando num aventureiro de 10 de vida
const ENEMY_DAMAGE_REFERENCE_HEALTH := 10.0
const ATTACK_BUFFER := 0.2
const PITCH_MIN := deg_to_rad(-60.0)
const PITCH_MAX := deg_to_rad(30.0)
const CAMERA_HEIGHT := 1.5
## folga entre a câmera deslocada para o lado e a parede que encosta nela
const CAMERA_WALL_MARGIN := 0.3
## longe da parede o ombro volta devagar; perto dela encolhe na hora, para não mostrar o outro lado
const SIDE_RECOVER_SPEED := 2.5
## espera pela resposta do host ao largar uma poção
const DROP_REPLY_TIMEOUT := 2.0
## tremor da camera de quem acerta: some sozinho em menos de meio segundo
const SHAKE_QUICK := 0.35
const SHAKE_HEAVY := 0.7
const SHAKE_DECAY := 2.5
const SHAKE_OFFSET := 0.14
const HIT_CONFIRM_PITCH_HEAVY := 0.75
const BASE_MOUSE_SENSITIVITY := 0.003
const BASE_STICK_SPEED := 2.8
const MOVE_DEADZONE := 0.1
const AIM_RANGE := 40.0
const AIM_LAYERS := 1 | 4
const REVIVE_RANGE := 2.2
const REVIVE_HEALTH_FRACTION := 0.5
## segurar o ataque alem disso vira golpe pesado; soltar antes e golpe rapido
const HEAVY_HOLD_TIME := 0.35
## segurar interagir bebe o item selecionado; o tempo segurando e o gole, exposto aos golpes
const DRINK_HOLD_TIME := 0.6
const REVIVE_READY_COLOR := Color(1.0, 0.88, 0.6)
const REVIVE_MISSING_COLOR := Color(0.62, 0.6, 0.58)
const MAX_ENERGY := 100.0
## ritmo de recarga comum a todos; cada classe ajusta com os multiplicadores
const BASE_REGEN := 24.0

## quao rapido a camera alcanca o aventureiro
@export var camera_follow_speed := 14.0
## forca com que empurra barris e caixotes
@export var push_force := 120.0
## continuar segurando depois do golpe pesado repete este golpe enquanto houver energia (giro do Barbarian)
@export var sustained_attack: Attack
## golpe do botao direito; vazio se a classe nao tem
@export var secondary_attack: Attack
## escudo do botao direito; vazio se a classe nao tem
@export var block: BlockAbility
## a roda para cima percorre esta lista; vazia = so o ataque principal
@export var abilities: Array[Attack] = []

## todos tem estamina (correr, escudo, golpes fisicos); quem usa mana paga os feiticos com ela
@export_group("Energia")
## paga os ataques com mana em vez de estamina
@export var uses_mana := false
## multiplica a recarga base da estamina
@export var stamina_regen_multiplier := 1.0
## multiplica a recarga base da mana
@export var mana_regen_multiplier := 1.0
## pausa depois de gastar estamina, antes de recarregar
@export var stamina_regen_delay := 0.9
## pausa depois de gastar mana, antes de recarregar
@export var mana_regen_delay := 1.0
## estamina ou mana zerada recarrega sem esperar a pausa
@export var recovers_when_empty := true
## custo do ataque, pago da mana se o aventureiro usa mana, senao da estamina
@export var quick_cost := 15.0
## custo do golpe pesado (segurar o ataque)
@export var heavy_cost := 35.0
## por segundo de corrida
@export var run_cost := 12.0
## segurar o escudo cansa bem devagar; sem estamina a guarda quebra
@export var block_cost := 2.0
## estamina gasta a cada golpe defendido
@export var block_hit_cost := 2.0
# o urro que o esqueletinho tanto pede (so o Barbarian)
@export var roars := false

var is_blocking := false
## 0 a 1; o deslocamento cresce com o quadrado para golpe leve tremer pouco
var shake_trauma := 0.0
## menu aberto em grupo: o mundo segue, mas o boneco para de obedecer e solta o que estava segurando
var input_locked := false:
	set(locked):
		input_locked = locked
		if locked:
			_attack_hold = -1.0
			_interact_hold = -1.0
			release_secondary()
## aliado caido ao alcance que da para reviver agora (precisa de pocao)
var revive_target: Adventurer
## baus e afins ao alcance: tocar E interage com eles em vez de comecar a beber
var interactables_in_reach := 0
var stamina: EnergyPool
## null em quem nao usa mana
var mana: EnergyPool

# o clique do analogico liga a corrida ate o boneco parar; no teclado corre enquanto segura Espaco
var _run_toggled := false
var _attack_buffer_left := 0.0
# -1 = botao solto; senao, ha quanto tempo o ataque esta segurado
var _attack_hold := -1.0
var _sustaining := false
var _interact_hold := -1.0
var _hinted_ally: Adventurer
var _ability_index := 0
var _world_items: Dictionary[String, int] = {}
var _drop_number := 0
## pedidos de largar poção esperando o host, na ordem em que saíram (a resposta volta na mesma ordem)
var _pending_drops: Array[QuickItem] = []
var _pending_drop_at := 0.0
var _aim_query := PhysicsRayQueryParameters3D.new()
var _framing := Vector2.ZERO
var _side := 0.0

@onready var camera_pivot: Node3D = $CameraPivot
## caído em grupo, a câmera acompanha este aliado em vez do próprio corpo; null volta para si
var camera_subject: Character
var grabbed_by: Mimic
var possessed_by: Mimic
var _escape_pressed_at := -1
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var name_tag: Label3D = $NameTag
@onready var health_bar: HealthBar3D = $HealthBar3D
@onready var revive_hint: Label3D = $ReviveHint
@onready var state_machine: AdventurerStateMachine = $StateMachine
@onready var inventory: QuickInventory = $Inventory
@onready var hit_confirm: AudioStreamPlayer = $HitConfirm


func _ready() -> void:
	super()
	add_to_group("players")
	died.connect(state_machine.change_state.bind("Dead"))
	if abilities.is_empty() and attack:
		abilities.append(attack)
	stamina = EnergyPool.new(MAX_ENERGY, BASE_REGEN * stamina_regen_multiplier, stamina_regen_delay)
	stamina.recovers_when_empty = recovers_when_empty
	stamina.locks_when_empty = true
	if uses_mana:
		mana = EnergyPool.new(MAX_ENERGY, BASE_REGEN * mana_regen_multiplier, mana_regen_delay)
		mana.recovers_when_empty = recovers_when_empty
	_aim_query.collision_mask = AIM_LAYERS
	_framing = Vector2(camera.h_offset, camera.v_offset)
	_side = _framing.x
	camera_pivot.global_position = global_position + Vector3.UP * CAMERA_HEIGHT
	if not is_multiplayer_authority():
		camera.current = false
		camera_pivot.process_mode = Node.PROCESS_MODE_DISABLED
		name_tag.show()
		health_bar.set_bar_visible(true)
	revived.connect(_on_revived)
	if Net.is_coop() and Net.friendly_fire:
		_allow_friendly_fire()


# a camera e top_level e segue a posicao interpolada, senao treme entre os passos de fisica
func _process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	var subject: Node3D = camera_subject if is_instance_valid(camera_subject) else self
	var target := subject.get_global_transform_interpolated().origin + Vector3.UP * CAMERA_HEIGHT
	camera_pivot.global_position = camera_pivot.global_position.lerp(target, minf(camera_follow_speed * delta, 1.0))
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look != Vector2.ZERO and (_is_spectating() or (not is_dead and _has_control())):
		_rotate_camera(look * BASE_STICK_SPEED * Settings.stick_sensitivity * delta)
	_shake_camera(delta)


## Fôlego de Escudeiro acelera a volta da estamina e da mana, inclusive a pausa antes de voltar
func get_energy_regen_factor() -> float:
	return maxf(1.0 + get_stat_bonus(StatModifier.Stat.ENERGY_REGEN), MIN_STAT_FACTOR)


func blessing_share() -> float:
	return 1.0


## o dano de inimigos e armadilhas vale como parte da vida base, sem bênção: um golpe de 1 tira 10% dela,
## e a vida ganha com Vigor fica de colchão. Fogo amigo continua em pontos
func _incoming_damage(amount: float, source: Node3D) -> float:
	if source is Adventurer:
		return amount
	return amount * max_health / ENEMY_DAMAGE_REFERENCE_HEALTH


func take_damage(amount: float, source: Node3D = null) -> void:
	var before := health
	super(amount, source)
	if source is Mimic and is_multiplayer_authority() and health < before:
		source.confirm_bite_damage(self)


func on_hit_landed(heavy: bool) -> void:
	super(heavy)
	if not is_multiplayer_authority():
		return
	shake_trauma = minf(shake_trauma + (SHAKE_HEAVY if heavy else SHAKE_QUICK), 1.0)
	hit_confirm.pitch_scale = HIT_CONFIRM_PITCH_HEAVY if heavy else 1.0
	hit_confirm.play()


func _shake_camera(delta: float) -> void:
	shake_trauma = move_toward(shake_trauma, 0.0, SHAKE_DECAY * delta)
	var strength := shake_trauma * shake_trauma * SHAKE_OFFSET
	var jitter := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength
	var safe := _safe_side_offset(_framing.x)
	_side = safe if absf(safe) < absf(_side) else move_toward(_side, safe, SIDE_RECOVER_SPEED * delta)
	camera.h_offset = _side + jitter.x
	camera.v_offset = _framing.y + jitter.y


## o enquadramento de ombro desloca a câmera para o lado depois do braço, que só confere a parede de
## trás: encostado numa muralha ou casa, esse lado atravessava a parede e mostrava o fora do mapa
func _safe_side_offset(side: float) -> float:
	if is_zero_approx(side):
		return 0.0
	var from := camera.global_position
	var to := from + camera.global_basis.x * (side + signf(side) * CAMERA_WALL_MARGIN)
	var query := PhysicsRayQueryParameters3D.create(from, to, spring_arm.collision_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return side
	return signf(side) * maxf(from.distance_to(hit.position) - CAMERA_WALL_MARGIN, 0.0)


func _physics_process(delta: float) -> void:
	super(delta)
	if not is_multiplayer_authority() or is_instance_valid(grabbed_by):
		return
	_push_bodies(delta)
	_attack_buffer_left -= delta
	if _run_toggled and _read_move_input().length() < MOVE_DEADZONE:
		_run_toggled = false
	if not is_dead:
		var regen_delta := delta * get_energy_regen_factor()
		if not _drain_for_running(delta) and not _drain_for_blocking(delta):
			stamina.regenerate(regen_delta)
		if mana:
			mana.regenerate(regen_delta)
	_track_attack_hold(delta)
	_keep_sustaining()
	_track_interact_hold(delta)
	if _attack_buffer_left > 0.0 and attack_toward_camera():
		_attack_buffer_left = 0.0
	_update_revive_target()


func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or not is_instance_valid(grabbed_by):
		return
	if event.is_action_pressed("attack", false) or event.is_action_released("attack"):
		var pressed := event.is_action_pressed("attack")
		if not pressed or _escape_pressed_at < 0:
			_escape_pressed_at = Time.get_ticks_msec() if pressed else -1
			grabbed_by._submit_escape_input.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, pressed)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") or event.is_action_pressed("pause") or event.is_action_pressed("drop_item"):
		get_viewport().set_input_as_handled()


func set_mimic_grab(mimic: Mimic) -> void:
	grabbed_by = mimic
	_escape_pressed_at = -1
	_attack_buffer_left = 0.0
	_attack_hold = -1.0
	_interact_hold = -1.0
	_sustaining = false
	if mimic:
		release_secondary()
		_end_action_locally()


func escape_hold_progress() -> float:
	if _escape_pressed_at < 0:
		return 0.0
	return clampf((Time.get_ticks_msec() - _escape_pressed_at) / (HEAVY_HOLD_TIME * 1000.0), 0.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if _is_spectating() and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not Settings.uses_gamepad():
		_rotate_camera(event.relative * BASE_MOUSE_SENSITIVITY * Settings.mouse_sensitivity)
		return
	if not is_multiplayer_authority() or input_locked or not state_machine.current_state.accepts_input():
		return
	var has_control := _has_control()
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not Settings.uses_gamepad():
		_rotate_camera(event.relative * BASE_MOUSE_SENSITIVITY * Settings.mouse_sensitivity)
	elif event.is_action_pressed("attack") and has_control:
		_attack_hold = 0.0
	elif event.is_action_released("attack"):
		if _attack_hold >= 0.0:
			_attack_hold = -1.0
			request_attack()
	elif event.is_action_pressed("secondary") and has_control and not is_blocking:
		use_secondary()
	elif event.is_action_released("secondary"):
		release_secondary()
	# um toque liga a corrida, no teclado e no controle; ela gasta sem parar e desliga ao parar de andar
	# ou ao zerar a estamina. Se valesse só segurando, tocar várias vezes correria pagando menos
	elif event.is_action_pressed("run"):
		_run_toggled = true
	elif event.is_action_pressed("interact"):
		if revive_target:
			revive_ally()
			get_viewport().set_input_as_handled()
		elif interactables_in_reach == 0:
			_interact_hold = 0.0
	elif event.is_action_pressed("next_ability") and has_control:
		next_ability()
	elif event.is_action_pressed("next_item") and has_control:
		inventory.select_next()
	elif event.is_action_pressed("drop_item") and has_control:
		drop_item()
		get_viewport().set_input_as_handled()


## o aventureiro que o jogador peer_id controla; null se ele saiu ou ainda nao nasceu
static func of_peer(tree: SceneTree, peer_id: int) -> Adventurer:
	for adventurer: Adventurer in tree.get_nodes_in_group("players"):
		if adventurer.get_multiplayer_authority() == peer_id:
			return adventurer
	return null


## pedido vindo da rede so vale de quem esta perto do que quer mexer; tiro pode chegar depois de
## o atirador cair, entao quem confere um tiro passa alive_only = false
static func peer_can_reach(tree: SceneTree, peer_id: int, point: Vector3, reach: float, alive_only := true) -> bool:
	var adventurer := of_peer(tree, peer_id)
	if adventurer == null or (alive_only and adventurer.is_dead):
		return false
	return adventurer.global_position.distance_to(point) <= reach


## só os aventureiros ganham a proteção por tentativas; os mortos-vivos ficam sem ela
func _extra_protection() -> float:
	return RunState.extra_protection()


func set_display_name(display_name: String) -> void:
	name_tag.text = display_name


func get_display_name() -> String:
	return name_tag.text if not name_tag.text.is_empty() else String(name)


func _allow_friendly_fire() -> void:
	_aim_query.collision_mask |= collision_layer
	for chosen: Attack in abilities + [secondary_attack]:
		if chosen is MeleeAttack:
			chosen.get_node("Hitbox").collision_mask |= collision_layer
		elif chosen is RangedAttack:
			chosen.target_layers |= collision_layer


func _on_revived() -> void:
	camera_subject = null
	state_machine.change_state("Idle")
	stamina.refill()
	if mana:
		mana.refill()
	if not is_multiplayer_authority():
		health_bar.set_bar_visible(true)
		health_bar.modulate.a = 1.0


func next_ability() -> void:
	if abilities.size() < 2:
		return
	_ability_index = (_ability_index + 1) % abilities.size()
	attack = abilities[_ability_index]
	ability_changed.emit()


func can_use(item: QuickItem) -> bool:
	return item.debuff != QuickItem.Debuff.NONE or item.heal_fraction > 0.0 or (item.mana_amount > 0.0 and mana != null)


## com a vida e a mana cheias o item nao e gasto
func use_item() -> bool:
	var item := inventory.selected()
	if item == null or is_dead or _drop_waiting():
		return false
	if item.debuff != QuickItem.Debuff.NONE:
		apply_debuff(item.debuff)
		_consume_item(item)
		potion_used.emit("%s por 5 segundos" % item.debuff_label())
		return true
	var restores_health := item.heal_fraction > 0.0 and health < get_max_health()
	var restores_mana := item.mana_amount > 0.0 and mana != null and mana.current < mana.maximum
	if not (restores_health or restores_mana):
		return false
	if restores_health:
		heal(get_max_health() * item.heal_fraction)
	if restores_mana:
		mana.restore(item.mana_amount)
	_consume_item(item)
	return true


## O host registra as poções distribuídas antes de autorizar alguém a largar uma delas.
func record_potion_pickup(item: QuickItem) -> bool:
	if not can_use(item):
		return false
	var path := item.resource_path
	var count := inventory.count_of(item) if is_multiplayer_authority() else int(_world_items.get(path, 0))
	if count >= item.max_carried:
		return false
	if not is_multiplayer_authority():
		_world_items[path] = count + 1
	return true


func _consume_item(item: QuickItem) -> void:
	inventory.take(item)
	if Net.is_online() and not multiplayer.is_server():
		_report_item_used.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, item.resource_path)


@rpc("authority", "reliable")
func _report_item_used(path: String) -> void:
	if multiplayer.is_server() and _world_items.has(path):
		_world_items[path] = maxi(_world_items[path] - 1, 0)


## a resposta do host pode nunca chegar (sala caiu, pacote perdido): passado esse tempo o jogador volta a
## beber e reviver. Cada resposta, mesmo atrasada, tira o item do seu pedido: largar de novo não duplica
func _drop_waiting() -> bool:
	return not _pending_drops.is_empty() and Time.get_ticks_msec() / 1000.0 - _pending_drop_at < DROP_REPLY_TIMEOUT


func drop_item() -> void:
	var item := inventory.selected()
	if item == null or is_dead or _drop_waiting() or not QuickItem.WORLD_SCENES.has(item.resource_path):
		return
	_pending_drops.append(item)
	_pending_drop_at = Time.get_ticks_msec() / 1000.0
	_request_drop.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER, item.resource_path)


@rpc("authority", "call_local", "reliable")
func _request_drop(path: String) -> void:
	if not multiplayer.is_server() or not QuickItem.WORLD_SCENES.has(path):
		return
	var item := load(path) as QuickItem
	var stock := inventory.count_of(item) if is_multiplayer_authority() else int(_world_items.get(path, 0))
	var forward := model.global_basis.z.normalized()
	var ahead := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.8, global_position + Vector3.UP * 0.8 + forward * 1.45, 1 | 8)
	var space := get_world_3d().direct_space_state
	var ground := PhysicsRayQueryParameters3D.create(ahead.to, ahead.to - Vector3.UP * 1.5, 1 | 8)
	var floor_hit := space.intersect_ray(ground)
	if is_dead or stock <= 0 or not space.intersect_ray(ahead).is_empty() or floor_hit.is_empty():
		_drop_reply.rpc_id(get_multiplayer_authority(), false)
		return
	if not is_multiplayer_authority():
		_world_items[path] = stock - 1
	_drop_number += 1
	_drop_reply.rpc_id(get_multiplayer_authority(), true)
	_spawn_dropped_potion.rpc(path, _drop_number, floor_hit.position)


@rpc("any_peer", "call_local", "reliable")
func _drop_reply(accepted: bool) -> void:
	if multiplayer.get_remote_sender_id() != MultiplayerPeer.TARGET_PEER_SERVER or _pending_drops.is_empty():
		return
	var item: QuickItem = _pending_drops.pop_front()
	if accepted:
		inventory.take(item)


@rpc("any_peer", "call_local", "reliable")
func _spawn_dropped_potion(path: String, number: int, spot: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != MultiplayerPeer.TARGET_PEER_SERVER:
		return
	var scene := load(QuickItem.WORLD_SCENES[path]) as PackedScene
	var potion := scene.instantiate() as Potion
	potion.name = "%sPocaoLargada%d" % [name, number]
	potion.armed = potion.item.debuff != QuickItem.Debuff.NONE
	var parent := get_parent()
	potion.position = (parent as Node3D).to_local(spot) if parent is Node3D else spot
	parent.add_child(potion)


## o item so e gasto quando o reviver vale; em grupo quem decide e a maquina do aliado caido,
## que confirma de volta (outro jogador pode ter revivido antes)
func revive_ally() -> void:
	if _drop_waiting() or inventory.first_healing() == null or not is_instance_valid(revive_target) or not revive_target.is_dead or is_instance_valid(revive_target.possessed_by):
		return
	var target := revive_target
	target.revive_hint.hide()
	revive_target = null
	if target.is_multiplayer_authority():
		spend_revive_item()
	target.revive(target.get_max_health() * REVIVE_HEALTH_FRACTION)


func spend_revive_item() -> void:
	var item := inventory.first_healing()
	if item:
		_consume_item(item)


func _update_revive_target() -> void:
	var nearest: Adventurer = null
	if not is_dead:
		for ally: Adventurer in get_tree().get_nodes_in_group("players"):
			if ally != self and ally.is_dead and not is_instance_valid(ally.possessed_by) and ally.global_position.distance_to(global_position) <= REVIVE_RANGE:
				nearest = ally
				break
	if nearest != _hinted_ally:
		if is_instance_valid(_hinted_ally):
			_hinted_ally.revive_hint.hide()
		_hinted_ally = nearest
	revive_target = nearest if nearest and inventory.first_healing() else null
	if nearest:
		_show_revive_hint(nearest)


# so aparece na tela de quem esta perto: o aviso fica no aliado caido, nao no HUD
func _show_revive_hint(ally: Adventurer) -> void:
	var item := inventory.first_healing()
	var key := "X" if Settings.uses_gamepad() else "E"
	var text := "%s  Reviver  (%s ×%d)" % [key, item.title, inventory.count_of(item)] if item else "Sem poção para reviver"
	if ally.revive_hint.text != text:
		ally.revive_hint.text = text
		ally.revive_hint.modulate = REVIVE_READY_COLOR if item else REVIVE_MISSING_COLOR
	ally.revive_hint.show()


func drink_progress() -> float:
	return _interact_hold / DRINK_HOLD_TIME if _interact_hold >= 0.0 else 0.0


func heavy_progress() -> float:
	return _attack_hold / HEAVY_HOLD_TIME if _attack_hold >= 0.0 else 0.0


func _push_bodies(delta: float) -> void:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var body := collision.get_collider() as RigidBody3D
		if body:
			var direction := -collision.get_normal().slide(Vector3.UP).normalized()
			body.apply_central_impulse(direction * push_force * delta)


func _has_control() -> bool:
	return not input_locked and not is_instance_valid(grabbed_by) and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or Settings.uses_gamepad())


func accepts_revive_from(sender: int) -> bool:
	return not is_instance_valid(possessed_by) and super(sender)


# so guarda o clique recusado porque o golpe anterior nao terminou; sem estamina ele nao espera
func request_attack() -> void:
	if not attack_toward_camera() and attack_pool().can_afford(cost_of(attack)):
		_attack_buffer_left = ATTACK_BUFFER


func attack_toward_camera() -> bool:
	return _attack_toward_camera(attack)


func heavy_attack() -> bool:
	return _attack_toward_camera(attack, true)


# o evento de soltar pode se perder (janela sem foco): sem o botao, so cancela
func _track_attack_hold(delta: float) -> void:
	if _attack_hold < 0.0:
		return
	if not (_has_control() and Input.is_action_pressed("attack")):
		_attack_hold = -1.0
		return
	_attack_hold += delta
	if _attack_hold >= HEAVY_HOLD_TIME:
		_attack_hold = -1.0
		_sustaining = heavy_attack() and sustained_attack != null


func _keep_sustaining() -> void:
	if not _sustaining:
		return
	if not (_has_control() and Input.is_action_pressed("attack")) or is_dead:
		_sustaining = false
		return
	if not sustained_attack.can_attack(self):
		return
	if not _attack_toward_camera(sustained_attack):
		_sustaining = false


func is_sustaining() -> bool:
	return _sustaining


# apanhar no meio do giro encerra o giro; para girar de novo, solta e segura outra vez
func _on_flinch() -> void:
	_sustaining = false


func _track_interact_hold(delta: float) -> void:
	if _interact_hold < 0.0:
		return
	if not Input.is_action_pressed("interact"):
		_interact_hold = -1.0
		return
	_interact_hold += delta
	if _interact_hold >= DRINK_HOLD_TIME:
		_interact_hold = -1.0
		use_item()


func _drain_for_running(delta: float) -> bool:
	var running := wants_to_run() and is_on_floor() and _read_move_input().length() >= MOVE_DEADZONE
	if not running:
		return false
	stamina.spend(run_cost * delta)
	if stamina.current == 0.0:
		_run_toggled = false
		energy_short.emit(stamina)
	return true


func _drain_for_blocking(delta: float) -> bool:
	if not is_blocking:
		return false
	stamina.spend(block_cost * delta)
	if stamina.current == 0.0:
		_break_guard()
	return true


func _break_guard() -> void:
	release_secondary()
	energy_short.emit(stamina)


func cost_of(chosen: Attack, heavy := false) -> float:
	if chosen.cost_override >= 0.0:
		return chosen.cost_override
	return heavy_cost if heavy else quick_cost


func attack_pool() -> EnergyPool:
	return mana if mana else stamina


func use_secondary() -> void:
	if block:
		_start_blocking()
	elif secondary_attack:
		_attack_toward_camera(secondary_attack)


func release_secondary() -> void:
	if is_blocking:
		_end_action()
		state_machine.change_state("Idle")


func _attack_toward_camera(chosen: Attack, heavy := false) -> bool:
	if not chosen or is_blocking or not chosen.can_attack(self):
		return false
	var cost := cost_of(chosen, heavy)
	var pool := attack_pool()
	if not pool.can_afford(cost):
		energy_short.emit(pool)
		return false
	face_camera()
	if not chosen.try_attack(self, heavy):
		return false
	pool.spend(cost)
	return true


func _start_blocking() -> void:
	if not can_act():
		return
	if stamina.is_exhausted():
		energy_short.emit(stamina)
		return
	face_camera()
	play_action(block.animation, 1.0, block.move_factor)
	state_machine.change_state("Block")


func face_camera() -> void:
	var forward := -camera_pivot.global_basis.z
	model.rotation.y = atan2(forward.x, forward.z) - global_rotation.y


func _blocks(source: Node3D) -> bool:
	if not (is_blocking and block.covers(self, source)):
		return false
	if not stamina.can_afford(block_hit_cost):
		_break_guard()
		return false
	stamina.spend(block_hit_cost)
	return true


## o raio comeca depois do personagem para nao bater em algo entre a camera e ele
func get_aim_point() -> Vector3:
	var center := get_viewport().get_visible_rect().size / 2.0
	var origin := camera.project_ray_origin(center)
	var direction := camera.project_ray_normal(center)
	var behind_player := origin.distance_to(camera_pivot.global_position)
	_aim_query.from = origin + direction * behind_player
	_aim_query.to = origin + direction * AIM_RANGE
	var hit := get_world_3d().direct_space_state.intersect_ray(_aim_query)
	return hit.position if hit else _aim_query.to


func _get_move_direction() -> Vector3:
	var input := _read_move_input()
	return camera_pivot.global_basis * Vector3(input.x, 0.0, input.y)


func _read_move_input() -> Vector2:
	if input_locked or is_instance_valid(grabbed_by):
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


func wants_to_run() -> bool:
	if stamina.is_exhausted() or input_locked or not is_multiplayer_authority():
		return false
	return _run_toggled or Input.is_action_pressed("run")


func _update_animation(direction: Vector3) -> void:
	state_machine.step(direction)


func _is_spectating() -> bool:
	return is_dead and is_multiplayer_authority() and is_instance_valid(camera_subject)


func _rotate_camera(amount: Vector2) -> void:
	var vertical := -amount.y if Settings.invert_y else amount.y
	camera_pivot.rotation.y -= amount.x
	spring_arm.rotation.x = clampf(spring_arm.rotation.x - vertical, PITCH_MIN, PITCH_MAX)
