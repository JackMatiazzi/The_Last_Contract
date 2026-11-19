class_name Enemy
extends Character

## altura do peito do alvo, onde mira quem ataca de longe
const AIM_HEIGHT := 1.0

@export var profile: EnemyProfile
## desligado, o cerebro nao decide nada (cenas paradas e testes)
@export var ai_enabled := true
## nasce deitado e so levanta quando acorda
@export var start_dormant := false
## nasce levantando do chao
@export var start_rising := false
## tempo que o corpo fica caido antes de afundar
@export var corpse_time := 6.0
## tempo afundando no chao
@export var sink_time := 1.5
## mancha deixada onde o corpo sumiu
@export var remains_scene: PackedScene
@export var rise_sound: AudioStreamPlayer3D
## ataque à distância de quem também bate de perto (o machado arremessado do elite); vazio = só o ataque
@export var throw_attack: RangedAttack
## o arremesso só sai com o alvo visto entre essas distâncias: mais perto ele prefere bater
@export var throw_min_distance := 3.5
@export var throw_max_distance := 10.0

var _corpse_timeline: Tween

@onready var perception: Perception = $Perception
@onready var brain: EnemyBrain = $EnemyBrain
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var health_bar: HealthBar3D = $HealthBar3D


func _ready() -> void:
	super()
	assert(profile, "%s: aponte um EnemyProfile no Inspector" % name)
	add_to_group(UndeadCensus.GROUP)
	died.connect(brain.change_state.bind("Dead"))
	died.connect(_clean_up_corpse)
	health_bar.visible = not start_dormant
	if start_rising:
		perception.acquire_target()
		if perception.target:
			perception.force_awareness(perception.target)
		brain.change_state("Awaken")
	else:
		brain.change_state("Dormant" if start_dormant else "Idle")


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		super(delta)
		return
	if ai_enabled and not is_dead:
		brain.physics_step(delta)
	else:
		brain.stop_moving()
	super(delta)
	if brain.has_look_point and not is_busy and not is_dead:
		_face(brain.look_point - global_position, delta)


func take_damage(amount: float, source: Node3D = null) -> void:
	super(amount, source)
	if is_dead or not is_multiplayer_authority():
		return
	var attacker := source as Character
	if attacker and attacker.is_in_group("players") and not attacker.is_dead:
		perception.provoke(attacker)
	else:
		perception.acquire_target()
		if perception.target != null:
			perception.force_awareness(perception.target)
	if brain.current_state_name == "Dormant" and ai_enabled:
		brain.change_state("Awaken")


## Quem ataca de longe mira no peito do alvo que está vendo; o corpo pode ainda estar virando.
## Sem alvo, mira para a frente como os outros personagens.
func get_aim_point() -> Vector3:
	var target := perception.target
	if target and is_instance_valid(target) and not target.is_dead:
		return target.global_position + Vector3.UP * AIM_HEIGHT
	return super()


## pode arremessar agora no alvo que está vendo, longe demais para o golpe
func can_throw_at(distance: float) -> bool:
	return throw_attack != null and distance >= throw_min_distance and distance <= throw_max_distance and throw_attack.can_attack(self)


func get_display_name() -> String:
	return profile.display_name


func _can_flinch() -> bool:
	return brain.current_state_name not in ["Dormant", "Awaken"]


func _clean_up_corpse() -> void:
	_corpse_timeline = create_tween()
	_corpse_timeline.tween_interval(corpse_time)
	_corpse_timeline.tween_callback(_leave_remains)
	_corpse_timeline.tween_property(self, "global_position:y", global_position.y - 1.2, sink_time)
	_corpse_timeline.tween_callback(queue_free)


func absorb_into(point: Vector3, duration: float) -> void:
	if _corpse_timeline:
		_corpse_timeline.kill()
	var timeline := create_tween().set_parallel()
	timeline.tween_property(self, "global_position", point + Vector3.DOWN * 1.2, duration).set_ease(Tween.EASE_IN)
	timeline.chain().tween_callback(queue_free)


func _leave_remains() -> void:
	if remains_scene == null:
		return
	var remains := remains_scene.instantiate() as Node3D
	remains.position = global_position
	remains.rotation.y = model.global_rotation.y
	get_parent().add_child(remains)


func _get_move_direction() -> Vector3:
	return brain.desired_direction if ai_enabled else Vector3.ZERO


func wants_to_run() -> bool:
	return ai_enabled and brain.wants_run


func share_brain_state(state_name: String) -> void:
	if is_broadcasting():
		_net_brain_state.rpc(state_name)


# nas outras maquinas o cerebro nao pensa; so o que aparece na tela acompanha o estado
@rpc("authority", "reliable")
func _net_brain_state(state_name: String) -> void:
	brain.current_state_name = state_name
	if state_name == "Awaken":
		health_bar.show()
		if rise_sound:
			rise_sound.play()
