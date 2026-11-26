class_name Chaser
extends Character
## quem nao usa o cerebro dos mortos-vivos mas, quando entra na briga, persegue o aventureiro mais perto e
## golpeia ao alcancar. So o host decide

## Golpeia o alvo a esta distancia (para um pouco antes, a 80%).
@export var strike_range := 1.9
## Alvo mais longe que isso e trocado pelo aventureiro mais perto.
@export var chase_range := 30.0

## o caminho pela navegacao e refeito a esse intervalo: o alvo anda, mas refazer todo quadro e caro
const PATH_REFRESH := 0.3
const WAYPOINT_REACHED := 0.6

var _target: Adventurer
var _path := PackedVector3Array()
var _path_index := 0
var _path_age := INF


func is_hunting() -> bool:
	return false


func _physics_process(delta: float) -> void:
	if is_multiplayer_authority() and is_hunting() and not is_dead:
		_hunt()
	super(delta)


func _hunt() -> void:
	if _target == null or _target.is_dead or _target.global_position.distance_to(global_position) > chase_range:
		_target = _nearest_player()
	if _target and _target.global_position.distance_to(global_position) <= strike_range:
		_look_toward(_target.global_position)
		attack.try_attack(self)


func _nearest_player() -> Adventurer:
	var nearest: Adventurer = null
	var nearest_distance := chase_range
	for player: Adventurer in get_tree().get_nodes_in_group("players"):
		var distance := player.global_position.distance_to(global_position)
		if not player.is_dead and distance < nearest_distance:
			nearest = player
			nearest_distance = distance
	return nearest


func _get_move_direction() -> Vector3:
	if not is_hunting() or _target == null or _target.global_position.distance_to(global_position) <= strike_range * 0.8:
		return Vector3.ZERO
	return (_next_point_toward(_target.global_position) - global_position).slide(Vector3.UP).normalized()


## em linha reta o perseguidor empacava na beira do terraço com o alvo embaixo: segue o caminho da
## navegação, que passa pela rampa. Sem mapa de navegação (testes, cenas soltas), vai direto
func _next_point_toward(goal: Vector3) -> Vector3:
	_path_age += get_physics_process_delta_time()
	if _path_age >= PATH_REFRESH:
		_path_age = 0.0
		var map := get_world_3d().navigation_map
		_path = NavigationServer3D.map_get_path(map, global_position, goal, true) if NavigationServer3D.map_get_iteration_id(map) > 0 else PackedVector3Array()
		_path_index = 0
	while _path_index < _path.size() and Vector2(_path[_path_index].x - global_position.x, _path[_path_index].z - global_position.z).length() < WAYPOINT_REACHED:
		_path_index += 1
	return _path[_path_index] if _path_index < _path.size() else goal


func _look_toward(point: Vector3) -> void:
	var to := (point - global_position).slide(Vector3.UP)
	if to.length() > 0.01:
		model.rotation.y = atan2(to.x, to.z) - global_rotation.y
