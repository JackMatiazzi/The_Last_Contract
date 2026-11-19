class_name EncounterSpawner
extends Node3D
## Gerenciador de pontos de nascimento (spawns) de jogadores, grupos de inimigos e chefes na fase.
## Responsável por selecionar aleatoriamente locais de nascimento e instanciar
## os grupos de inimigos garantindo uma distância mínima em relação à posição inicial dos jogadores.

## pontos possiveis de nascimento do jogador
@export var player_spots: Node3D
## pontos possiveis dos grupos de inimigos
@export var group_spots: Node3D
## onde o boss surge
@export var boss_spot: Marker3D
@export var group_scenes: Array[PackedScene] = []
## grupos sorteados por tentativa
@export var group_count := 7
## os grupos nascem pelo menos a esta distancia do jogador
@export var min_distance_from_player := 16.0
## a zona da entrada sempre recebe o grupo mais facil, para o primeiro encontro ensinar
@export var easy_zone: StringName
@export var easy_group: PackedScene
## pontos possiveis dos baus; a cada tentativa so alguns viram bau, e um deles e mimico
@export var chest_spots: Node3D
@export var chest_scene: PackedScene
@export var mimic_scene: PackedScene
@export var chest_count := 5
## os mímicos vêm além dos baús: um por jogador da partida
@export var mimics_per_player := 1

## Escolhe aleatoriamente um dos marcadores de posição reservados para os jogadores.
func pick_player_spot() -> Marker3D:
	return _markers(player_spots).pick_random()

## Instancia e posiciona os grupos de inimigos no mapa, respeitando a distância mínima do jogador.
func spawn_groups(player_position: Vector3) -> Array[EnemyGroup]:
	var spots := _markers(group_spots).filter(func(spot: Marker3D) -> bool:
		return spot.global_position.distance_to(player_position) >= min_distance_from_player)
	spots.shuffle()
	spots = _spread_by_zone(spots)
	var scenes := group_scenes.duplicate()
	scenes.shuffle()
	var spawned: Array[EnemyGroup] = []
	for i in mini(group_count, spots.size()):
		var scene: PackedScene = scenes[i % scenes.size()]
		if easy_group and spots[i].get_meta("zone", null) == easy_zone:
			scene = easy_group
		var group := scene.instantiate() as EnemyGroup
		group.name = "Group%d" % i
		group.transform = global_transform.affine_inverse() * spots[i].global_transform
		add_child(group)
		spawned.append(group)
	return spawned

## Sorteia os baus da tentativa entre os pontos (espalhados por zona, como os grupos) e quais deles sao
## mimicos. Usa a mesma semente dos grupos, entao todas as maquinas do grupo veem os mesmos baus.
func spawn_chests(players := 1) -> Array[Node3D]:
	var spawned: Array[Node3D] = []
	if chest_spots == null or chest_scene == null:
		return spawned
	var spots: Array = _markers(chest_spots)
	spots.shuffle()
	spots = _spread_by_zone(spots)
	var mimics := players * mimics_per_player if mimic_scene else 0
	var total := mini(chest_count + mimics, spots.size())
	if total < chest_count + mimics:
		push_warning("faltam pontos de baú: %d pedidos, %d pontos" % [chest_count + mimics, spots.size()])
	var roles: Array[bool] = []
	for i in total:
		roles.append(i < mimics)
	roles.shuffle()
	for i in total:
		var is_mimic := roles[i]
		var chest := (mimic_scene if is_mimic else chest_scene).instantiate() as Node3D
		chest.name = ("Mimic%d" if is_mimic else "Chest%d") % i
		chest.transform = global_transform.affine_inverse() * spots[i].global_transform
		add_child(chest)
		spawned.append(chest)
	return spawned

## pontos com metadata zone (grupos e baús): primeiro um em cada zona, depois os a mais em zonas que ainda
## têm só um, para não amontoar. Pontos sem zona (mapas antigos) entram todos, como antes
func _spread_by_zone(spots: Array) -> Array:
	var per_zone := {}
	var first_round := []
	var second_round := []
	for spot: Marker3D in spots:
		var zone: Variant = spot.get_meta("zone", null)
		if zone == null:
			first_round.append(spot)
			continue
		var count: int = per_zone.get(zone, 0)
		if count == 0:
			first_round.append(spot)
		elif count == 1:
			second_round.append(spot)
		else:
			continue
		per_zone[zone] = count + 1
	return first_round + second_round

## Retorna todos os nós do tipo Marker3D que são filhos diretos do nó pai informado.
func _markers(parent: Node3D) -> Array[Marker3D]:
	var found: Array[Marker3D] = []
	found.assign(parent.get_children().filter(func(child: Node) -> bool: return child is Marker3D))
	return found
