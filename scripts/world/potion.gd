class_name Potion
extends Area3D
## vai para o inventario de quem passa por cima e consegue usar (a de mana so para quem tem mana) e
## quebra com golpe ou projetil. Em grupo o host decide quem pegou: dois jogadores na mesma pocao nao
## levam uma cada

const PICK_UP_REACH := 3.0

## item guardado no inventario de quem pega
@export var item: QuickItem
@export var model: Node3D
@export var pickup_sound: AudioStreamPlayer3D
@export var break_sound: AudioStreamPlayer3D
## O frasco fixo do calabouço alterna de lacre nas tentativas pares.
@export var alternate_item: QuickItem

## Poções de vida da mesma fonte compartilham esta lista de quem já pegou uma.
var collected_by: Dictionary[int, bool] = {}

var _consumed := false
var armed := false


func _ready() -> void:
	if alternate_item and RunState.attempt % 2 == 0:
		item = alternate_item
		var seal := model.get_node("Lacre") as MeshInstance3D
		var material := seal.get_active_material(0).duplicate() as StandardMaterial3D
		material.albedo_color = item.seal_color
		material.emission = item.seal_color * 0.7
		seal.material_override = material
		var glow := model.get_node("Glow") as OmniLight3D
		glow.light_color = item.seal_color
	if armed:
		collision_mask = 4
		body_entered.connect(_trigger_trap)
		return
	body_entered.connect(_try_pick_up)
	body_exited.connect(_stop_waiting)


func _trigger_trap(body: Node3D) -> void:
	var enemy := body as Character
	if not multiplayer.is_server() or _consumed or not enemy or enemy is Adventurer or enemy.is_dead:
		return
	enemy.apply_debuff(item.debuff)
	_vanish.rpc(true)


# com o limite cheio a pocao fica no chao esperando: gastar uma em cima dela ja pega esta
func _try_pick_up(body: Node3D) -> void:
	var adventurer := body as Adventurer
	if adventurer == null or adventurer.is_dead or not adventurer.is_multiplayer_authority() or _consumed:
		return
	if not adventurer.can_use(item):
		return
	if adventurer.inventory.count_of(item) >= item.max_carried:
		if not adventurer.inventory.changed.is_connected(_try_pick_up):
			adventurer.inventory.changed.connect(_try_pick_up.bind(adventurer), CONNECT_ONE_SHOT)
		return
	_request_pick_up.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER)


func _stop_waiting(body: Node3D) -> void:
	var adventurer := body as Adventurer
	if adventurer and adventurer.inventory.changed.is_connected(_try_pick_up):
		adventurer.inventory.changed.disconnect(_try_pick_up)


func shatter() -> void:
	if not _consumed:
		_request_shatter.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER)


@rpc("any_peer", "call_local", "reliable")
func _request_pick_up() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or armed or _consumed or collected_by.has(sender):
		return
	if not Adventurer.peer_can_reach(get_tree(), sender, global_position, PICK_UP_REACH):
		return
	var adventurer := Adventurer.of_peer(get_tree(), sender)
	if not adventurer or not adventurer.record_potion_pickup(item):
		return
	collected_by[sender] = true
	_give.rpc_id(sender)
	_vanish.rpc(false)


@rpc("authority", "call_local", "reliable")
func _give() -> void:
	var adventurer := Adventurer.of_peer(get_tree(), multiplayer.get_unique_id())
	if adventurer:
		adventurer.inventory.add(item)


@rpc("any_peer", "call_local", "reliable")
func _request_shatter() -> void:
	if not _consumed and Adventurer.peer_can_reach(get_tree(), multiplayer.get_remote_sender_id(), global_position, Character.REMOTE_HIT_REACH, false):
		_vanish.rpc(true)


@rpc("authority", "call_local", "reliable")
func _vanish(broken: bool) -> void:
	if _consumed:
		return
	_consumed = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	model.hide()
	var sound := break_sound if broken else pickup_sound
	sound.play()
	sound.finished.connect(queue_free)
