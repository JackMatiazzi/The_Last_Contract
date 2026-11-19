class_name Summoner
extends Node3D

@export var minion_scene: PackedScene
## tropa fixa levantada a cada invocação (ex.: dois de espada, um mago, um arqueiro); vazia usa
## minion_scene per_cast vezes
@export var wave: Array[PackedScene] = []
## tempo entre as invocacoes
@export var interval := 9.0
## lacaios por invocacao
@export var per_cast := 2
## maximo de lacaios vivos ao mesmo tempo
@export var max_alive := 4
## distancia dos lacaios em volta de quem invoca
@export var radius := 2.5
@export var animation := "Spellcast_Summon"
## espera entre o gesto e os lacaios aparecerem
@export var raise_delay := 0.7
@export var sound: AudioStreamPlayer3D

var minions: Array[Enemy] = []
var _cooldown_left := 0.0
var _raised := 0

@onready var owner_enemy: Enemy = get_parent() as Enemy


func _ready() -> void:
	_cooldown_left = interval * 0.5
	owner_enemy.died.connect(_release_minions)


func _physics_process(delta: float) -> void:
	if not owner_enemy.is_multiplayer_authority() or owner_enemy.is_dead or not _is_hunting():
		return
	_cooldown_left -= delta
	if _cooldown_left <= 0.0 and owner_enemy.can_act() and _alive_count() < max_alive:
		summon()


func summon() -> void:
	_cooldown_left = interval
	owner_enemy.play_action(animation)
	if sound:
		sound.play()
	await get_tree().create_timer(raise_delay).timeout
	if owner_enemy.is_dead:
		return
	var kinds := _kinds_to_raise(max_alive - _alive_count())
	var count := kinds.size()
	var spots := PackedVector3Array()
	for i in count:
		var angle := TAU * i / count + randf() * 0.6
		spots.append(owner_enemy.global_position + Vector3(cos(angle), 0, sin(angle)) * radius)
	if owner_enemy.is_broadcasting():
		_net_raise_minions.rpc(spots, _raised, kinds)
	_raise_minions(spots, _raised, kinds)


## quais lacaios levantar agora, como índices da tropa (-1 = minion_scene), sem passar do limite de vivos
func _kinds_to_raise(room: int) -> PackedInt32Array:
	var kinds := PackedInt32Array()
	if wave.is_empty():
		for i in mini(per_cast, room):
			kinds.append(-1)
	else:
		for i in mini(wave.size(), room):
			kinds.append(i)
	return kinds


@rpc("authority", "reliable")
func _net_raise_minions(spots: PackedVector3Array, first_index: int, kinds: PackedInt32Array) -> void:
	if kinds.size() == spots.size() and Array(kinds).all(func(kind: int) -> bool: return kind >= -1 and kind < wave.size()):
		_raise_minions(spots, first_index, kinds)


# nome fixo para o lacaio ter o mesmo caminho em todas as maquinas
func _raise_minions(spots: PackedVector3Array, first_index: int, kinds: PackedInt32Array) -> void:
	for i in spots.size():
		var scene := minion_scene if kinds[i] < 0 else wave[kinds[i]]
		var minion := scene.instantiate() as Enemy
		minion.name = "%sMinion%d" % [owner_enemy.name, first_index + i]
		minion.position = owner_enemy.get_parent().to_local(spots[i])
		minion.start_rising = true
		owner_enemy.get_parent().add_child(minion)
		minions.append(minion)
	_raised = first_index + spots.size()


func _is_hunting() -> bool:
	return owner_enemy.brain.current_state_name in ["Chase", "Attack"]


# o lacaio caido some do jogo depois de afundar, mas continua na lista ate aqui
func _alive_count() -> int:
	minions.assign(minions.filter(func(minion: Variant) -> bool: return is_instance_valid(minion) and not (minion as Enemy).is_dead))
	return minions.size()


func _release_minions() -> void:
	if not owner_enemy.is_multiplayer_authority():
		return
	for minion in minions:
		if is_instance_valid(minion) and not minion.is_dead:
			minion.take_damage(minion.health)
