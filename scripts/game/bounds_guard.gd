class_name BoundsGuard
extends Node
## quem cai para fora do mapa, ou para em cima de muralha ou telhado sem caminho de volta, reaparece no
## último chão seguro. Cada máquina cuida só do próprio aventureiro, como o resto do movimento

const CHECK_INTERVAL := 0.5
## somando o tempo no chão fora do caminho (zera ao voltar para ele): dá para pular num caixote sem ser puxado
const STRANDED_LIMIT := 3.0
const MAX_ROUTE_GAP := 3.0
const MAX_ROUTE_RISE := 2.5
const SAFE_SNAP := 0.6
const RETURN_LINE := "Você voltou para o caminho."

@export var session: GameSession
## abaixo disso é queda para fora do mapa: uns metros abaixo do chão mais baixo da fase
@export var fall_limit_y := -6.0

var _anchor := Vector3.INF
var _safe := Vector3.INF
var _stranded := 0.0
var _check_left := 0.0


func _physics_process(delta: float) -> void:
	var player := session.player if session else null
	if player == null or player.is_dead or not player.is_multiplayer_authority():
		return
	if _safe == Vector3.INF:
		_safe = player.global_position
	if player.global_position.y < fall_limit_y:
		_return(player)
		return
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = CHECK_INTERVAL
	if player.is_on_floor():
		_check_ground(player)


func _check_ground(player: Adventurer) -> void:
	var map := player.get_world_3d().navigation_map
	var here := player.global_position
	if not NavigationServer3D.map_get_closest_point_owner(map, here).is_valid():
		return
	if _anchor == Vector3.INF:
		_anchor = here
		return
	var path := NavigationServer3D.map_get_path(map, _anchor, here, true)
	if path.is_empty():
		return
	var route_end := path[path.size() - 1]
	var gap := Vector2(route_end.x - here.x, route_end.z - here.z).length()
	if gap > MAX_ROUTE_GAP or here.y - route_end.y > MAX_ROUTE_RISE:
		_stranded += CHECK_INTERVAL
		if _stranded >= STRANDED_LIMIT:
			_return(player)
		return
	_stranded = 0.0
	if gap < SAFE_SNAP and absf(here.y - route_end.y) < 1.0:
		_safe = here


func _return(player: Adventurer) -> void:
	_stranded = 0.0
	player.global_position = _safe + Vector3.UP * 0.1
	player.velocity = Vector3.ZERO
	# sem isso a interpolação de física desliza o corpo e a câmera do ponto antigo até o seguro
	player.reset_physics_interpolation()
	if session.hud:
		session.hud.announce(RETURN_LINE)
	Playtest.record("out_of_bounds", {"position": _safe})
