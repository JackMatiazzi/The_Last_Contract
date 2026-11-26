class_name Mimic
extends Chaser
## parece um bau ate alguem tentar abrir ou bater nele: entao morde quem mexeu e persegue aos pulos o
## aventureiro mais perto. So o host decide, como os mortos-vivos; derrotado, solta o tesouro de verdade. Nao
## e morto-vivo, entao nao entra na conta do contrato

const OPEN_REACH := 3.0
const SINK_DEPTH := 1.2
const GRAB_WINDUP := 0.55
const BITE_WINDOW_MS := 7000
const ESCAPE_STEP_TIME := 1.7
const ESCAPE_SEQUENCE := [false, true, false, true]
const STOLEN_SHOT_RANGE := 7.0

@export var prompt: Label3D
@export var open_area: Area3D
## Dentes e lingua: escondidos ate ele acordar.
@export var mouth: Node3D
@export var loot_scene: PackedScene
@export var keyboard_prompt := "E  Abrir"
@export var gamepad_prompt := "X  Abrir"
## o corpo fica um tempo depois de soltar o tesouro e então afunda no chão, como o dos mortos-vivos
@export var corpse_time := 20.0
@export var sink_time := 1.5

var is_awake := false
var _player: Adventurer
var grabbed: Adventurer
var possessed: Adventurer
var escape_step := 0
var _last_bitten: Adventurer
var _bite_count := 0
var _last_bite_at := 0
var _pending_bites: Dictionary[int, int] = {}
var _grabbing := false
var _escape_left := 0.0
var _pressed_at := -1
var _attempted_assimilation := false
var _stolen_attack: Attack
var _possessed_name := ""
var _use_stolen_melee := false

@onready var health_bar: HealthBar3D = $HealthBar3D


func _ready() -> void:
	super()
	assert(prompt and open_area and mouth and loot_scene, "Mimic: aponte prompt, open_area, mouth e loot_scene")
	prompt.hide()
	health_bar.set_bar_visible(false)
	open_area.body_entered.connect(_on_body_entered)
	open_area.body_exited.connect(_on_body_exited)
	(attack as MeleeAttack).hitting_character.connect(_expect_bite_confirmation)


func get_display_name() -> String:
	return "Mímico" if _possessed_name.is_empty() else _possessed_name


func get_max_health() -> float:
	return super() if _possessed_name.is_empty() else max_health


func take_damage(amount: float, source: Node3D = null) -> void:
	super(amount, source)
	if is_multiplayer_authority() and not is_dead and not is_awake:
		_wake(source as Adventurer)


func is_hunting() -> bool:
	return is_awake and not _grabbing and not is_instance_valid(grabbed)


func wants_to_run() -> bool:
	return is_awake


func _physics_process(delta: float) -> void:
	if is_instance_valid(grabbed):
		_escape_left -= delta
		if is_multiplayer_authority():
			if grabbed.is_dead:
				_net_end_grab.rpc(false)
			elif _escape_left <= 0.0:
				_assimilate()
	var falling := velocity.y < -1.0
	super(delta)
	if falling and is_multiplayer_authority() and is_awake and not is_dead and not _attempted_assimilation and not _grabbing:
		for index in get_slide_collision_count():
			var hit := get_slide_collision(index)
			var adventurer := hit.get_collider() as Adventurer
			if adventurer and hit.get_normal().y > 0.5:
				_start_grab(adventurer)
				break


func _expect_bite_confirmation(body: Character) -> void:
	if not _attempted_assimilation and body is Adventurer and not body.is_multiplayer_authority():
		_pending_bites[body.get_multiplayer_authority()] = Time.get_ticks_msec()


func confirm_bite_damage(adventurer: Adventurer) -> void:
	if is_multiplayer_authority():
		_register_bite(adventurer)
	else:
		_confirm_remote_bite.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER)


@rpc("any_peer", "reliable")
func _confirm_remote_bite() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if not _pending_bites.has(peer):
		return
	var contact := _pending_bites[peer]
	_pending_bites.erase(peer)
	if Time.get_ticks_msec() - contact <= 2000:
		_register_bite(Adventurer.of_peer(get_tree(), peer))


func _register_bite(adventurer: Adventurer) -> void:
	if _attempted_assimilation or not is_instance_valid(adventurer) or adventurer.is_dead:
		return
	var now := Time.get_ticks_msec()
	if _last_bitten != adventurer or now - _last_bite_at > BITE_WINDOW_MS:
		_bite_count = 0
	_last_bitten = adventurer
	_last_bite_at = now
	_bite_count += 1


func _hunt() -> void:
	if not _attempted_assimilation and _bite_count >= 2 and is_instance_valid(_last_bitten) and Time.get_ticks_msec() - _last_bite_at <= BITE_WINDOW_MS and attack.can_attack(self) and _can_grab(_last_bitten):
		_start_grab(_last_bitten)
		return
	if _stolen_attack and is_instance_valid(_target) and not _target.is_dead:
		var distance := global_position.distance_to(_target.global_position)
		if _stolen_attack is RangedAttack and distance > strike_range and distance <= STOLEN_SHOT_RANGE:
			_look_toward(_target.global_position)
			_stolen_attack.try_attack(self)
			return
		if _stolen_attack is MeleeAttack and distance <= strike_range and attack.can_attack(self):
			_look_toward(_target.global_position)
			var chosen := _stolen_attack if _use_stolen_melee else attack
			if chosen.try_attack(self):
				_use_stolen_melee = not _use_stolen_melee
			return
	super()


func get_aim_point() -> Vector3:
	if _stolen_attack and is_instance_valid(_target):
		return _target.global_position + Vector3.UP * 1.1
	return super()


func _can_grab(adventurer: Adventurer) -> bool:
	return is_instance_valid(adventurer) and not adventurer.is_dead and not is_instance_valid(adventurer.grabbed_by) and global_position.distance_to(adventurer.global_position) <= strike_range + 0.35 and (attack as MeleeAttack)._has_clear_line(self, adventurer)


func escape_seconds_left() -> float:
	return maxf(_escape_left, 0.0)


func _start_grab(adventurer: Adventurer) -> void:
	if _attempted_assimilation or _grabbing or not _can_grab(adventurer):
		return
	_grabbing = true
	_look_toward(adventurer.global_position)
	play_action("Bite")
	attack.sound.play()
	var action := action_id
	await get_tree().create_timer(GRAB_WINDUP, false).timeout
	_grabbing = false
	if not is_dead and action_id == action and _can_grab(adventurer):
		_attempted_assimilation = true
		_net_begin_grab.rpc(adventurer.get_path())


@rpc("authority", "call_local", "reliable")
func _net_begin_grab(target_path: NodePath) -> void:
	grabbed = get_node_or_null(target_path) as Adventurer
	if not is_instance_valid(grabbed) or grabbed.is_dead:
		grabbed = null
		return
	grabbed.set_mimic_grab(self)
	escape_step = 0
	_escape_left = ESCAPE_STEP_TIME
	_pressed_at = -1


@rpc("any_peer", "call_local", "reliable")
func _submit_escape_input(pressed: bool) -> void:
	if not multiplayer.is_server() or not is_instance_valid(grabbed) or grabbed.is_dead:
		return
	if grabbed.get_multiplayer_authority() != multiplayer.get_remote_sender_id():
		return
	_escape_input(pressed, Time.get_ticks_msec())


func _escape_input(pressed: bool, now: int) -> void:
	if pressed:
		if _pressed_at < 0:
			_pressed_at = now
		return
	if _pressed_at < 0:
		return
	var heavy := now - _pressed_at >= roundi(Adventurer.HEAVY_HOLD_TIME * 1000.0)
	_pressed_at = -1
	if heavy != ESCAPE_SEQUENCE[escape_step]:
		_assimilate()
	elif escape_step == ESCAPE_SEQUENCE.size() - 1:
		_net_end_grab.rpc(true)
	else:
		_net_escape_step.rpc(escape_step + 1)


@rpc("authority", "call_local", "reliable")
func _net_escape_step(step: int) -> void:
	escape_step = step
	_escape_left = ESCAPE_STEP_TIME


@rpc("authority", "call_local", "reliable")
func _net_end_grab(escaped: bool) -> void:
	if is_instance_valid(grabbed):
		grabbed.set_mimic_grab(null)
	grabbed = null
	_grabbing = false
	_end_action_locally()
	if escaped and is_multiplayer_authority():
		knockback_velocity = -model.global_basis.z.normalized() * 4.0


func launch_away_from(source: Node3D, speed: float, lift: float) -> void:
	if is_multiplayer_authority() and is_instance_valid(grabbed) and source is Adventurer and source != grabbed:
		_net_end_grab.rpc(true)
	super(source, speed, lift)


func _assimilate() -> void:
	if is_instance_valid(grabbed) and not grabbed.is_dead:
		_net_possess.rpc(grabbed.get_path(), health + grabbed.health, grabbed.global_position)


@rpc("authority", "call_local", "reliable")
func _net_possess(target_path: NodePath, combined_health: float, spot: Vector3) -> void:
	var victim := get_node_or_null(target_path) as Adventurer
	if not is_instance_valid(victim) or not _possessed_name.is_empty():
		return
	_net_end_grab(false)
	possessed = victim
	_possessed_name = "Possuído · %s" % victim.get_display_name()
	global_position = spot
	_apply_appearance(victim)
	max_health = combined_health
	health = combined_health
	health_changed.emit(health, max_health)
	victim.possessed_by = self
	victim.camera_subject = self
	victim.model.hide()
	victim.name_tag.hide()
	if victim.is_multiplayer_authority() and not victim.is_dead:
		victim._lose_health(victim.health, self)


func _apply_appearance(victim: Adventurer) -> void:
	var shell := (load(victim.scene_file_path) as PackedScene).instantiate() as Adventurer
	var body := shell.model
	var body_collision := shell.get_node("CollisionShape3D") as CollisionShape3D
	collision_shape.set_deferred("shape", body_collision.shape)
	collision_shape.set_deferred("position", body_collision.position)
	_stolen_attack = shell.attack
	animation_player.stop()
	animation_player = shell.animation_player
	animation_player.animation_finished.connect(_on_animation_finished)
	for child in body.get_children():
		if child is Attack and child != _stolen_attack:
			continue
		child.owner = null
		body.remove_child(child)
		model.add_child(child)
	model.scale = body.scale
	_replace_head(animation_player.get_parent() as Node3D)
	health_bar.position.y = 2.22
	attack.animations = PackedStringArray([_stolen_attack.animations[0]])
	if _stolen_attack is RangedAttack:
		_stolen_attack.target_layers = 2
	elif _stolen_attack is MeleeAttack:
		_stolen_attack.hitbox.collision_mask = 2
	shell.free()
	var label := Label3D.new()
	label.text = _possessed_name
	label.position.y = 2.6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 0.48, 0.5)
	add_child(label)


func _replace_head(appearance: Node3D) -> void:
	var skeleton := appearance.get_node("Rig/Skeleton3D") as Skeleton3D
	var original_head := appearance.find_child("%s_Head" % appearance.name, true, false) as MeshInstance3D
	original_head.hide()
	for accessory in skeleton.get_children():
		if accessory is BoneAttachment3D and accessory.bone_name == "head":
			accessory.hide()
	var attachment := BoneAttachment3D.new()
	attachment.name = "CabecaDoMimico"
	attachment.bone_name = "head"
	skeleton.add_child(attachment)
	var chest := model.get_node("Bau") as Node3D
	chest.reparent(attachment, false)
	chest.position = Vector3(0.0, 0.01, 0.0)
	chest.rotation = Vector3.ZERO
	chest.scale = Vector3.ONE * 0.68
	var lid := chest.get_node("chest/chest_lid") as Node3D
	lid.rotation.x = -0.85
	chest.show()
	mouth.show()


func _wake(opener: Adventurer) -> void:
	_net_wake.rpc()
	_target = opener if opener else _nearest_player()
	if _target:
		_look_toward(_target.global_position)
		attack.try_attack(self)


@rpc("authority", "call_local", "reliable")
func _net_wake() -> void:
	is_awake = true
	mouth.show()
	prompt.hide()
	health_bar.set_bar_visible(true)
	if _player:
		_player.interactables_in_reach -= 1
		_player = null


func die() -> void:
	if is_multiplayer_authority() and is_instance_valid(possessed):
		_net_release_possessed.rpc(global_position)
	super()


@rpc("authority", "call_local", "reliable")
func _net_release_possessed(spot: Vector3) -> void:
	if not is_instance_valid(possessed):
		return
	possessed.possessed_by = null
	possessed.camera_subject = _nearest_player()
	possessed.global_position = spot
	possessed.reset_physics_interpolation()
	possessed.model.show()
	if not possessed.is_multiplayer_authority():
		possessed.name_tag.show()
	possessed = null


# o tesouro cai em todas as maquinas com o mesmo nome, para a pocao ser a mesma em todas
func _die_locally() -> void:
	_net_end_grab(false)
	super()
	LootDrop.spawn(get_parent(), loot_scene, "%sLoot" % name, global_position + model.global_basis.z * 1.4)
	var sink := create_tween()
	sink.tween_interval(corpse_time)
	sink.tween_property(self, "global_position:y", global_position.y - SINK_DEPTH, sink_time)
	sink.tween_callback(queue_free)


func _unhandled_input(event: InputEvent) -> void:
	if _player and not is_awake and not is_dead and not _player.is_dead and event.is_action_pressed("interact"):
		_request_open.rpc_id(MultiplayerPeer.TARGET_PEER_SERVER)
		get_viewport().set_input_as_handled()


@rpc("any_peer", "call_local", "reliable")
func _request_open() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not is_awake and not is_dead and Adventurer.peer_can_reach(get_tree(), sender, global_position, OPEN_REACH):
		_wake(Adventurer.of_peer(get_tree(), sender))


# igual a um bau: o aviso de abrir aparece para quem chega perto
func _on_body_entered(body: Node3D) -> void:
	var adventurer := body as Adventurer
	if adventurer and adventurer.is_multiplayer_authority() and _player == null and not is_awake and not is_dead:
		_player = adventurer
		adventurer.interactables_in_reach += 1
		prompt.text = gamepad_prompt if Settings.uses_gamepad() else keyboard_prompt
		prompt.show()


func _on_body_exited(body: Node3D) -> void:
	if body == _player:
		_player.interactables_in_reach -= 1
		_player = null
		prompt.hide()
