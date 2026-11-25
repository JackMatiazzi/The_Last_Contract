class_name RangedAttack
extends Attack

@export var projectile_scene: PackedScene
## camadas que o projetil acerta
@export_flags_3d_physics var target_layers := 4

@export_group("Pesado - Disparo Multiplo")
## quantidade de flechas no ataque pesado (1 = normal; 2 = tiro duplo do Rogue)
@export var heavy_projectile_count := 1
## intervalo em segundos entre cada flecha no MODO RAJADA
@export var heavy_burst_interval := 0.12
## abertura em graus entre as flechas no MODO LEQUE
@export var heavy_spread_degrees := 6.0

@onready var muzzle: Marker3D = $Muzzle


func _perform(attacker: Character, total_damage: float, heavy: bool) -> void:
	var direction := (attacker.get_aim_point() - muzzle.global_position).normalized()
	if attacker.is_broadcasting():
		_net_fire.rpc(attacker.get_path(), muzzle.global_position, direction, total_damage, heavy)
	#_fire(attacker, muzzle.global_position, direction, total_damage, heavy)
	_execute_shot(attacker, muzzle.global_position, direction, total_damage, heavy)

func _execute_shot(attacker: Character, origin: Vector3, direction: Vector3, total_damage: float, heavy: bool) -> void:
	var count := heavy_projectile_count if heavy else 1
	if count <= 1:
		_fire(attacker, origin, direction, total_damage, heavy)
		return

	# =========================================================================
	# MODO 1 (ATIVO): RAJADA (atira uma flecha atras da outra)
	# Para testar o Modo 2, comente este bloco e descomente o bloco de baixo.
	# =========================================================================
	#for i in count:
		#if i > 0:
			#await get_tree().create_timer(heavy_burst_interval).timeout
			#if not is_instance_valid(attacker) or attacker.is_dead:
				#return
			## Atualiza a posicao da ponta do arco e a mira para a 2a flecha acompanhar o movimento
			#origin = muzzle.global_position
			#direction = (attacker.get_aim_point() - origin).normalized()
		#_fire(attacker, origin, direction, total_damage, heavy)

	# =========================================================================
	# MODO 2 (COMENTADO): LEQUE (atira as flechas ao mesmo tempo abertas)
	# Selecione as linhas abaixo e aperte Ctrl+K no Godot para ativar.
	# =========================================================================
	var step := deg_to_rad(heavy_spread_degrees)
	var start := -step * (count - 1) * 0.5
	for i in count:
		var spread_dir := direction.rotated(Vector3.UP, start + step * i).normalized()
		_fire(attacker, origin, spread_dir, total_damage, heavy)

func _fire(attacker: Character, origin: Vector3, direction: Vector3, total_damage: float, heavy: bool) -> void:
	var projectile := projectile_scene.instantiate() as Projectile
	attacker.get_parent().add_child(projectile)
	projectile.launch(attacker, origin, direction, total_damage, target_layers)
	projectile.breaks_props = heavy


# o projetil voa em todas as maquinas, mas so o do atirador causa dano
@rpc("any_peer", "reliable")
func _net_fire(attacker_path: NodePath, origin: Vector3, direction: Vector3, total_damage: float, heavy: bool) -> void:
	var attacker := get_node_or_null(attacker_path) as Character
	if attacker == null or multiplayer.get_remote_sender_id() != attacker.get_multiplayer_authority():
		return
	if not (origin.is_finite() and direction.is_finite()) or direction.length() < 0.001 or not Character.is_valid_remote_amount(total_damage):
		return
	_fire(attacker, origin, direction.normalized(), total_damage, heavy)
