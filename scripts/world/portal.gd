class_name Portal
extends Area3D
## metade de um par: aventureiro, morto-vivo comum e projetil que entram aqui saem na frente do outro portal;
## elite e chefe nao passam (crosses_portals).
## Cada maquina so move o proprio aventureiro, e a rede leva a posicao nova aos outros

const GROUP := "portals"
## centro e raio do veu, no meio da altura do aventureiro
const RING_CENTER := Vector3(0.0, 1.1, 0.0)
const RING_RADIUS := 0.75
const TRAVEL_COOLDOWN := 0.5
## sai a frente do portal de destino, longe o bastante para nao entrar nele de volta
const EXIT_OFFSET := 1.4
## a saida so vale se a navegacao liga o chao dela ao proprio portal por um caminho curto: a frente pode
## ser muralha, parapeito baixo ou a beira de uma rampa, e quem saia ali ficava em cima da muralha
const EXIT_MAX_WALK := 3.0
const EXIT_NAV_GAP := 0.8
## quem chega junto nao sai no mesmo ponto: um em cima do outro, a fisica empurrava todos para cima
const CHARACTER_LAYERS := 2 | 4
const CROWD_RADIUS := 0.45
const CROWD_STEP := 1.0
## a fisica so ve o corpo no lugar novo no passo seguinte: quem chega no mesmo quadro olha a lista
const CLAIM_TIME := 0.3
const CLOSE_TIME := 0.4
const WORLD_LAYER := 1
const VIEW_SCALE := 0.5
## folga do plano de corte: a camera do outro lado nao enxerga o que esta atras do portal
const NEAR_MARGIN := 0.3
const TURN_AROUND := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
## largura da textura da barra de tempo, em pixels
const TIME_BAR_WIDTH := 100.0

## quanto tempo o par fica aberto
@export var lifetime := 12.0
@export var visual: Node3D
@export var travel_sound: AudioStreamPlayer3D
@export var veil: MeshInstance3D
@export var view: SubViewport
@export var view_camera: Camera3D
## a barra acima do anel esvazia ate o portal fechar
@export var time_fill: Sprite3D

## ao ligar o par, o tempo dos dois começa a correr; o primeiro portal sozinho espera o segundo
var link: Portal:
	set(other):
		link = other
		if is_linked():
			_start_closing()

var _showing := false
var _age := 0.0
var _closing := false
## saidas entregues ha pouco: {"spot", "until"}
var _claimed: Array[Dictionary] = []


func _ready() -> void:
	assert(visual and travel_sound and veil and view and view_camera and time_fill, "Portal: aponte os nos exportados")
	add_to_group(GROUP)
	body_entered.connect(_on_body_entered)
	if is_linked():
		_start_closing()


func _start_closing() -> void:
	if _closing or not is_inside_tree():
		return
	_closing = true
	var timeline := create_tween()
	timeline.tween_interval(lifetime)
	timeline.tween_property(visual, "scale", Vector3.ZERO, CLOSE_TIME)
	timeline.tween_callback(queue_free)


func is_linked() -> bool:
	return link != null and is_instance_valid(link)


## o portal ligado cujo veu o trecho de from a to atravessa primeiro; null se nenhum
static func first_crossed(tree: SceneTree, from: Vector3, to: Vector3) -> Portal:
	var first: Portal = null
	var nearest := INF
	for portal: Portal in tree.get_nodes_in_group(GROUP):
		var fraction := portal.crossing_fraction(from, to)
		if fraction >= 0.0 and fraction < nearest:
			first = portal
			nearest = fraction
	return first


## em que fracao do trecho o veu e cruzado, de qualquer lado; -1 se passa ao lado ou nao chega
func crossing_fraction(from: Vector3, to: Vector3) -> float:
	if not is_linked():
		return -1.0
	var start := to_local(from)
	var end := to_local(to)
	if (start.z > 0.0) == (end.z > 0.0) or is_equal_approx(start.z, end.z):
		return -1.0
	var fraction := start.z / (start.z - end.z)
	var spot := start.lerp(end, fraction)
	if Vector2(spot.x, spot.y - RING_CENTER.y).length() > RING_RADIUS:
		return -1.0
	return fraction


## leva uma posicao e direcao deste lado para o outro portal: de qualquer lado que se entre,
## sai pela frente do par. A camera da janela e os projeteis usam a mesma conta
func carry(through: Transform3D, came_from: Vector3) -> Transform3D:
	var relative := global_transform.affine_inverse() * through
	if to_local(came_from).z < 0.0:
		relative = TURN_AROUND * relative
	return link.global_transform * relative


func time_left_fraction() -> float:
	return clampf(1.0 - _age / lifetime, 0.0, 1.0)


func _process(delta: float) -> void:
	if _closing:
		_age += delta
	time_fill.region_rect.size.x = TIME_BAR_WIDTH * time_left_fraction()
	var eye := get_viewport().get_camera_3d()
	var showing := is_linked() and eye != null
	if showing != _showing:
		_showing = showing
		veil.set_instance_shader_parameter(&"linked", showing)
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if showing else SubViewport.UPDATE_DISABLED
	if showing:
		_follow(eye)


# a camera do outro lado repete a posicao do olho em relacao a este portal
func _follow(eye: Camera3D) -> void:
	var wanted := Vector2i(Vector2(get_viewport().get_visible_rect().size) * VIEW_SCALE)
	if view.size != wanted:
		view.size = wanted
	view_camera.global_transform = carry(eye.global_transform, eye.global_position)
	view_camera.fov = eye.fov
	view_camera.near = maxf(eye.near, absf(to_local(eye.global_position).z) - NEAR_MARGIN)


# recarga e som em todas as maquinas; so o dono do personagem move o boneco (os mortos-vivos sao do host)
func _on_body_entered(body: Node3D) -> void:
	var traveler := body as Character
	if traveler == null or traveler.is_dead or not traveler.crosses_portals or not is_linked():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if traveler.get_meta(&"portal_ready_at", 0.0) > now:
		return
	var point: Variant
	if traveler.is_multiplayer_authority():
		point = link.free_exit_point(traveler)
		if point == null:
			return
	traveler.set_meta(&"portal_ready_at", now + TRAVEL_COOLDOWN)
	travel_sound.play()
	if point != null:
		# fora do meio da consulta de fisica que disparou o sinal
		_send_through.call_deferred(traveler, point)


func _send_through(traveler: Character, point: Vector3) -> void:
	if is_instance_valid(traveler):
		traveler.global_position = point
		traveler.reset_physics_interpolation()


## a saída livre mais próxima em chão da mesma altura e ligado ao portal
func free_exit_point(traveler: Character) -> Variant:
	var point := exit_point()
	var space := get_world_3d().direct_space_state
	for offset in [0.0, CROWD_STEP, -CROWD_STEP, 2.0 * CROWD_STEP, -2.0 * CROWD_STEP]:
		var candidate: Vector3 = point + global_basis.x * offset
		var ground := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP, candidate + Vector3.DOWN, WORLD_LAYER)
		var floor_hit := space.intersect_ray(ground)
		if floor_hit.is_empty() or absf(floor_hit.position.y - point.y) > 0.5:
			continue
		var spot: Vector3 = floor_hit.position
		if _claimed_near(spot) or _occupied(space, spot, CHARACTER_LAYERS, traveler):
			continue
		if not _is_walkable_exit(spot) or (offset != 0.0 and _occupied(space, spot, WORLD_LAYER, traveler)):
			continue
		_claim(spot)
		return spot
	return null


func _claimed_near(spot: Vector3) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	_claimed = _claimed.filter(func(claim: Dictionary) -> bool: return claim.until > now)
	return _claimed.any(func(claim: Dictionary) -> bool: return claim.spot.distance_to(spot) < CROWD_RADIUS * 2.0)


func _claim(spot: Vector3) -> void:
	_claimed.append({"spot": spot, "until": Time.get_ticks_msec() / 1000.0 + CLAIM_TIME})


## dentro de parede ou em cima de alguem, a fisica empurra o corpo para cima ao chegar
func _occupied(space: PhysicsDirectSpaceState3D, spot: Vector3, layers: int, traveler: Character) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = CROWD_RADIUS
	query.shape = shape
	query.transform = Transform3D(Basis(), spot + Vector3.UP * 0.9)
	query.collision_mask = layers
	query.exclude = [traveler.get_rid()]
	return not space.intersect_shape(query, 1).is_empty()


## a frente do portal, no chao; com parede no caminho sai no proprio portal (a recarga evita voltar)
func exit_point() -> Vector3:
	var space := get_world_3d().direct_space_state
	var ahead := global_position - global_basis.z * EXIT_OFFSET
	var wall := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, ahead + Vector3.UP, WORLD_LAYER)
	if not space.intersect_ray(wall).is_empty():
		ahead = global_position
	var ground := PhysicsRayQueryParameters3D.create(ahead + Vector3.UP * 1.5, ahead + Vector3.DOWN * 3.0, WORLD_LAYER)
	var hit := space.intersect_ray(ground)
	var point: Vector3 = hit.position if hit else ahead
	return point if _is_walkable_exit(point) else global_position


## a saída precisa de um caminho curto até o portal
func _is_walkable_exit(point: Vector3) -> bool:
	var session := get_parent() as GameSession
	if session and not session.allows_portal_at(point):
		return false
	var map := get_world_3d().navigation_map
	if not NavigationServer3D.map_get_closest_point_owner(map, global_position).is_valid():
		return true
	var home := NavigationServer3D.map_get_closest_point(map, global_position)
	var near := NavigationServer3D.map_get_closest_point(map, point)
	var path := NavigationServer3D.map_get_path(map, home, near, true)
	var walk := 0.0
	for i in range(1, path.size()):
		walk += path[i - 1].distance_to(path[i])
	var reachable := not path.is_empty() and path[path.size() - 1].distance_to(near) < 0.1 and walk <= EXIT_MAX_WALK
	return reachable and near.distance_to(point) <= EXIT_NAV_GAP
